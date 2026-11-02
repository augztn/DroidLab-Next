import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter/material.dart';
import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/backend_providers.dart';

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({required this.child, required this.currentLocation, super.key});
  final Widget child;
  final String currentLocation;
  @override ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  bool _expanded = true;
  final List<String> _consoleLines = [];
  StreamSubscription<BackendEvent>? _events;
  BackendClient? _eventClient;
  Timer? _deviceRefreshTimer;
  Timer? _consoleFlushTimer;
  final List<String> _pendingConsoleLines = [];
  Timer? _operationLogFlushTimer;
  final List<String> _pendingOperationLogLines = [];
  String? _pendingDeviceToolRoute;
  Future<void> _logWriteQueue = Future<void>.value();
  IOSink? _operationLogSink;
  int _operationLogBytes = 0;
  static const _maxOperationLogBytes = 5 * 1024 * 1024;
  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('WORKSPACE', [('Dashboard','/dashboard',Icons.grid_view_rounded),('Device Manager','/devices',Icons.devices_rounded)]),
    ('FIRMWARE', [('Firmware & Payload','/firmware',Icons.folder_open_rounded)]),
    ('DEVICE TOOLS', [('ADB Toolkit','/adb',Icons.terminal_rounded),('Fastboot Toolkit','/fastboot',Icons.memory_rounded),('Android Debloater','/debloater',Icons.cleaning_services_rounded)]),
    ('OBSERVABILITY', [('Logs & Diagnostics','/logs',Icons.receipt_long_rounded),('Operation History','/history',Icons.history_rounded)]),
  ];

  @override
  void initState() {
    super.initState();
    _deviceRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && ref.read(backendReadyProvider).hasValue) {
        ref.invalidate(deviceListProvider);
      }
    });

  }

  Future<void> _subscribeToBackendEvents(BackendClient client) async {
    if (identical(_eventClient, client)) return;
    final previousSubscription = _events;
    _events = null;
    _eventClient = client;
    await previousSubscription?.cancel();
    if (!mounted || !identical(_eventClient, client)) return;
    _events = client.events.listen((event) {
      if (!mounted || !identical(_eventClient, client)) return;
      late final String line;
      if (event is BackendOutput) {
        line = '[${event.stream}] ${event.line}';
      } else if (event is BackendPreflight) {
        line = '[preflight] ${event.target}: ${event.command.join(' ')}';
      } else if (event is BackendAccepted) {
        line = '[accepted] ${event.requestId}';
      } else {
        return;
      }
      final timestamp = DateTime.now().toIso8601String();
      // Keep detailed output and preflight commands in the live console only.
      // The durable log stores event categories, never device IDs, paths,
      // command arguments, or arbitrary command output.
      final persistedEvent = event is BackendOutput
          ? '[output omitted]'
          : event is BackendPreflight
              ? '[preflight details omitted]'
              : '[operation accepted]';
      unawaited(_appendOperationLog('$timestamp $persistedEvent'));
      _pendingConsoleLines.add('$timestamp $line');
      // Coalesce bursts of ADB/logcat output into one UI update. ADB can emit
      // hundreds of lines per second; rebuilding the entire desktop shell for
      // every line creates avoidable frame work.
      _consoleFlushTimer ??= Timer(const Duration(milliseconds: 100), () {
        _consoleFlushTimer = null;
        if (!mounted || _pendingConsoleLines.isEmpty) return;
        setState(() {
          _consoleLines.addAll(_pendingConsoleLines);
          _pendingConsoleLines.clear();
          if (_consoleLines.length > 300) {
            _consoleLines.removeRange(0, _consoleLines.length - 300);
          }
          ref.read(operationConsoleLinesProvider.notifier).state = List.unmodifiable(_consoleLines);
        });
      });
    });
  }

  String get _operationLogPath {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ?? Directory.current.path;
    return '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs${Platform.pathSeparator}operations.log';
  }

  Future<void> _appendOperationLog(String line) {
    _pendingOperationLogLines.add(line);
    _operationLogFlushTimer ??= Timer(const Duration(seconds: 1), () {
      _operationLogFlushTimer = null;
      unawaited(_drainOperationLog());
    });
    return _logWriteQueue;
  }

  Future<void> _drainOperationLog() {
    if (_pendingOperationLogLines.isEmpty) return _logWriteQueue;
    final batch = List<String>.of(_pendingOperationLogLines);
    _pendingOperationLogLines.clear();
    _logWriteQueue = _logWriteQueue.then((_) async {
      try {
        final file = File(_operationLogPath);
        await file.parent.create(recursive: true);
        final encoded = utf8.encode('${batch.join('\n')}\n');
        if (_operationLogSink == null) {
          _operationLogBytes = await file.exists() ? await file.length() : 0;
          if (_operationLogBytes >= _maxOperationLogBytes) {
            for (var index = 3; index >= 1; index--) {
              final source = File('${file.path}.$index');
              final destination = File('${file.path}.${index + 1}');
              if (await destination.exists()) await destination.delete();
              if (await source.exists()) await source.rename(destination.path);
            }
            if (await file.exists()) await file.rename('${file.path}.1');
            _operationLogBytes = 0;
          }
          _operationLogSink = file.openWrite(mode: FileMode.writeOnlyAppend);
        }
        if (_operationLogBytes + encoded.length > _maxOperationLogBytes) {
          await _operationLogSink!.flush();
          await _operationLogSink!.close();
          _operationLogSink = null;
          final rotated = File('${file.path}.1');
          if (await rotated.exists()) await rotated.delete();
          if (await file.exists()) await file.rename(rotated.path);
          _operationLogBytes = 0;
          _operationLogSink = file.openWrite(mode: FileMode.writeOnlyAppend);
        }
        _operationLogSink!.add(encoded);
        _operationLogBytes += encoded.length;
        await _operationLogSink!.flush();
      } catch (_) {
        // Logging must never interrupt device operations or UI event handling.
      }
    });
    return _logWriteQueue;
  }

  @override
  void dispose() {
    _deviceRefreshTimer?.cancel();
    _consoleFlushTimer?.cancel();
    _pendingConsoleLines.clear();
    _operationLogFlushTimer?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    unawaited(_closeOperationLog());
    super.dispose();
  }

  Future<void> _closeOperationLog() async {
    try {
      await _drainOperationLog();
      await _logWriteQueue;
      await _operationLogSink?.flush();
      await _operationLogSink?.close();
    } catch (_) {
      // Shutdown should not be blocked by a log-file failure.
    } finally {
      _operationLogSink = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendReadyProvider);
    if (backend.hasValue) {
      unawaited(_subscribeToBackendEvents(ref.read(backendClientProvider)));
    }
    final devices = ref.watch(deviceListProvider);
    final detectedToolRoute = devices.valueOrNull == null
        ? null
        : preferredDeviceToolLocation(devices.valueOrNull!);
    if ((widget.currentLocation == '/adb' ||
            widget.currentLocation == '/fastboot') &&
        detectedToolRoute != null &&
        detectedToolRoute != widget.currentLocation &&
        _pendingDeviceToolRoute != detectedToolRoute) {
      _pendingDeviceToolRoute = detectedToolRoute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final destination = _pendingDeviceToolRoute;
        _pendingDeviceToolRoute = null;
        if (destination != null &&
            (widget.currentLocation == '/adb' ||
                widget.currentLocation == '/fastboot')) {
          context.go(destination);
        }
      });
    }
    final targetSerial = ref.watch(selectedTargetSerialProvider);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 1000;
      final expanded = _expanded && !compact;
      final colors = Theme.of(context).colorScheme;
      final discovered = devices.valueOrNull?['devices'] as List<dynamic>? ?? const [];
      if (targetSerial != null && devices.hasValue &&
          !discovered.whereType<Map<String, dynamic>>().any((device) => device['serial'] == targetSerial)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(selectedTargetSerialProvider) == targetSerial) {
            ref.read(selectedTargetSerialProvider.notifier).state = null;
          }
        });
      }
      return Scaffold(body: SafeArea(child: Column(children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.go('/dashboard'),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/branding/droidlab_app_icon.png', width: 36, height: 36, fit: BoxFit.contain),
                    const SizedBox(width: 10),
                    Flexible(child: Text('DroidLab', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: -0.5,
                      ),
                    )),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: expanded ? 276 : (constraints.maxWidth < 620 ? 56 : 64),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(children: [
              SizedBox(
                height: 48,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 4),
                  child: Row(children: [
                    if (expanded) Expanded(child: Text(
                      'Target: ${targetSerial ?? 'Unselected'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                    )),
                    IconButton(
                      tooltip: 'Toggle sidebar width',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: const Icon(Icons.menu, size: 19),
                    ),
                  ]),
                ),
              ),
              Expanded(child: ListView(
                padding: EdgeInsets.fromLTRB(expanded ? 10 : 5, 8, expanded ? 10 : 5, 14),
                children: [
                  for (final group in _groups) ...[
                    if (expanded) Padding(
                      padding: const EdgeInsets.fromLTRB(13, 20, 8, 9),
                      child: Text(
                        group.$1 == 'FIRMWARE' ? 'Firmware & OTA' :
                        group.$1 == 'OBSERVABILITY' ? 'Observability' :
                        group.$1 == 'WORKSPACE' ? 'Workspace' : 'Device Tools',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final item in group.$2)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: expanded ? 3 : 2),
                        child: Tooltip(
                          message: item.$1,
                          child: Material(
                            color: expanded
                                ? colors.surface
                                : widget.currentLocation == item.$2
                                    ? colors.primaryContainer.withValues(alpha: 0.72)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            clipBehavior: Clip.antiAlias,
                            child: expanded
                                ? ListTile(
                                    selected: widget.currentLocation == item.$2,
                                    leading: Icon(item.$3, size: 19),
                                    title: Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                    minLeadingWidth: 24,
                                    minTileHeight: 48,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                    onTap: () => context.go(item.$2),
                                  )
                                : SizedBox(
                                    height: 46,
                                    child: InkWell(
                                      onTap: () => context.go(item.$2),
                                      child: Center(child: Icon(
                                        item.$3,
                                        size: 20,
                                        color: widget.currentLocation == item.$2
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      )),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ],
              )),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(expanded ? 8 : 5, 8, expanded ? 8 : 5, 10),
                child: Column(children: [
                  for (final entry in <(String, String, IconData)>[
                    ('Settings', '/settings', Icons.settings_outlined),
                    ('About DroidLab', '/about', Icons.info_outline),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Tooltip(
                        message: entry.$1,
                        child: Material(
                          color: expanded
                              ? colors.surface
                              : widget.currentLocation == entry.$2
                                  ? colors.primaryContainer.withValues(alpha: 0.72)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          clipBehavior: Clip.antiAlias,
                          child: expanded
                              ? ListTile(
                                  leading: Icon(entry.$3, size: 19),
                                  title: Text(entry.$1),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  minTileHeight: 44,
                                  selected: widget.currentLocation == entry.$2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                  onTap: () => context.go(entry.$2),
                                )
                              : SizedBox(
                                  height: 44,
                                  child: InkWell(
                                    onTap: () => context.go(entry.$2),
                                    child: Center(child: Icon(
                                      entry.$3,
                                      size: 20,
                                      color: widget.currentLocation == entry.$2
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                    )),
                                  ),
                                ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(child: Padding(
            padding: EdgeInsets.fromLTRB(constraints.maxWidth < 620 ? 12 : compact ? 16 : 28, constraints.maxWidth < 620 ? 14 : compact ? 18 : 28, constraints.maxWidth < 620 ? 12 : compact ? 16 : 28, 18),
            child: widget.child,
          )),
        ])),

      ])));
    });
  }
}
