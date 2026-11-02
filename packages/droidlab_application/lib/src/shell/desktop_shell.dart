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
  bool _consoleVisible = true;
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
    ('DEVICE TOOLS', [('ADB Toolkit','/adb',Icons.terminal_rounded),('Fastboot Toolkit','/fastboot',Icons.memory_rounded),('Android Debloater','/debloater',Icons.cleaning_services_rounded),('Feature Lab','/studio',Icons.auto_awesome_rounded)]),
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
        });
      });
    });
  }

  @override
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
      final surfaces = Theme.of(context).extension<DroidLabThemeSurfaces>();
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
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => context.go('/dashboard'),
              child: Text('DroidLab', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: -0.5,
              )),
            ),
            const Spacer(),
            if (!compact) ...[
              for (final item in const [
                ('Dashboard', '/dashboard'),
                ('Devices', '/devices'),
                ('Payload', '/firmware'),
                ('Debloater', '/debloater'),
                ('Feature Lab', '/studio'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: InkWell(
                    onTap: () => context.go(item.$2),
                    child: Text(item.$1, style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.currentLocation == item.$2 ? colors.primary : colors.onSurfaceVariant,
                      fontWeight: widget.currentLocation == item.$2 ? FontWeight.w600 : FontWeight.w500,
                    )),
                  ),
                ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: () => context.go('/settings'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              child: const Text('Workstation Settings'),
            ),
          ]),
        ),
        Expanded(child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: expanded ? 282 : 64,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
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
              Expanded(child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                children: [
                  for (final group in _groups) ...[
                    if (expanded) Padding(
                      padding: const EdgeInsets.fromLTRB(12, 15, 8, 7),
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
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Tooltip(
                          message: item.$1,
                          child: Material(
                            color: colors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              selected: widget.currentLocation == item.$2,
                              leading: Icon(item.$3, size: 19),
                              title: expanded ? Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                              contentPadding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
                              dense: true,
                              minLeadingWidth: 22,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                              onTap: () => context.go(item.$2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              )),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(children: [
                  Material(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(9),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Icons.settings_outlined, size: 19),
                      title: expanded ? const Text('Settings') : null,
                      contentPadding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
                      dense: true,
                      selected: widget.currentLocation == '/settings',
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      onTap: () => context.go('/settings'),
                    ),
                  ),
                  Material(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(9),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Icons.info_outline, size: 19),
                      title: expanded ? const Text('About DroidLab') : null,
                      contentPadding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
                      dense: true,
                      selected: widget.currentLocation == '/about',
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      onTap: () => context.go('/about'),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          Expanded(child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 14 : 29, compact ? 14 : 28, compact ? 14 : 29, 18),
            child: widget.child,
          )),
        ])),
        if (_consoleVisible)
          Container(
            height: compact ? 176 : 220,
            decoration: BoxDecoration(
              color: surfaces?.console ?? colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(children: [
              SizedBox(
                height: 42,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(Icons.terminal, color: colors.primary, size: 17),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Operation Console (Bounded 300-line JSONL Event Stream)',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                    )),
                    TextButton.icon(
                      onPressed: () => setState(_consoleLines.clear),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _consoleVisible = false),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 17),
                      label: const Text('Hide'),
                      style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _consoleLines.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Align(alignment: Alignment.topLeft, child: Text(
                      'Backend output and preflight events will stream here.',
                      style: TextStyle(fontFamily: 'monospace', color: Color(0xFFEDF4FB)),
                    )),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    itemCount: _consoleLines.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _consoleLines[_consoleLines.length-index-1],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace', color: const Color(0xFFEDF4FB),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ),
            ]),
          )
        else
          Container(
            height: 36,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: surfaces?.console ?? colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: TextButton.icon(
              onPressed: () => setState(() => _consoleVisible = true),
              icon: const Icon(Icons.terminal, size: 16),
              label: const Text('Show'),
              style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
            ),
          ),
      ])));
    });
  }
}
