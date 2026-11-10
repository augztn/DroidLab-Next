import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter/material.dart';
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
  bool _consoleExpanded = true;
  final List<String> _consoleLines = [];
  StreamSubscription<BackendEvent>? _events;
  BackendClient? _eventClient;
  Timer? _deviceRefreshTimer;
  Timer? _consoleFlushTimer;
  final List<String> _pendingConsoleLines = [];
  Timer? _operationLogFlushTimer;
  final List<String> _pendingOperationLogLines = [];
  String? _lastModePromptKey;
  bool _modePromptOpen = false;
  Future<void> _logWriteQueue = Future<void>.value();
  IOSink? _operationLogSink;
  int _operationLogBytes = 0;
  static const _maxOperationLogBytes = 5 * 1024 * 1024;
  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('WORKSPACE', [('Dashboard','/dashboard',Icons.grid_view_rounded),('Device Manager','/devices',Icons.devices_rounded)]),
    ('FIRMWARE', [('Firmware & Payload','/firmware',Icons.folder_open_rounded)]),
    ('DEVICE TOOLS', [('ADB Toolkit','/adb',Icons.terminal_rounded),('Fastboot Toolkit','/fastboot',Icons.memory_rounded)]),
    ('APPLICATIONS', [('App Manager','/apps',Icons.apps_rounded),('Android Debloater','/debloater',Icons.cleaning_services_rounded)]),
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
  void didUpdateWidget(covariant DesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation != widget.currentLocation) {
      _lastModePromptKey = null;
    }
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


  Widget _buildOperationConsole(BuildContext context, ColorScheme colors) {
    final border = BorderSide(color: colors.outlineVariant);
    return Container(
      decoration: BoxDecoration(color: colors.surface, border: Border(top: border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(Icons.terminal, size: 17, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Operation Console (Bounded 300-line JSONL Event Stream)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              )),
              IconButton(
                tooltip: 'Clear console',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _consoleLines.clear();
                  _pendingConsoleLines.clear();
                  ref.read(operationConsoleLinesProvider.notifier).state = const [];
                }),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
              Tooltip(
                message: _consoleExpanded ? 'Hide console' : 'Show console',
                child: TextButton.icon(
                onPressed: () => setState(() => _consoleExpanded = !_consoleExpanded),
                icon: Icon(_consoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 18),
                label: Text(_consoleExpanded ? 'Hide' : 'Show'),
                ),
              ),
              const SizedBox(width: 8),
            ]),
          ),
          if (_consoleExpanded)
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.17).clamp(112.0, 160.0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.surfaceContainerLowest, border: Border(top: border)),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: _consoleLines.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      _consoleLines[index],
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _maybePromptForDeviceToolMode(
    Map<String, dynamic>? data,
    String? selectedSerial,
  ) {
    if (!mounted || _modePromptOpen ||
        (widget.currentLocation != '/adb' && widget.currentLocation != '/fastboot') ||
        data == null) {
      return;
    }
    final suggestion = deviceToolModeSwitchSuggestion(
      data,
      currentLocation: widget.currentLocation,
      selectedSerial: selectedSerial,
    );
    if (suggestion == null) return;
    final destination = suggestion['destination']!;
    final state = suggestion['state']!;
    final serial = suggestion['serial']!;
    final key = '$serial:$state:$destination:${widget.currentLocation}';
    if (_lastModePromptKey == key) return;
    _lastModePromptKey = key;
    _modePromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.currentLocation !=
          (destination == '/fastboot' ? '/adb' : '/fastboot')) {
        _modePromptOpen = false;
        return;
      }
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(destination == '/fastboot' ? Icons.memory_rounded : Icons.phone_android_rounded),
          title: Text(destination == '/fastboot'
              ? 'Device detected in Fastboot mode'
              : 'Device detected in Android (ADB) mode'),
          content: Text(destination == '/fastboot'
              ? '$serial is currently in $state mode. ADB commands are unavailable in this mode. Switch to Fastboot Toolkit to continue with bootloader or Fastbootd operations.'
              : '$serial is back in Android mode. Fastboot commands are unavailable in this mode. Switch to ADB Toolkit to continue with Android device operations.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Stay here')),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) context.go(destination);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(destination == '/fastboot' ? 'Open Fastboot Toolkit' : 'Open ADB Toolkit'),
            ),
          ],
        ),
      )).whenComplete(() { _modePromptOpen = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendReadyProvider);
    if (backend.hasValue) {
      unawaited(_subscribeToBackendEvents(ref.read(backendClientProvider)));
    }
    final devices = ref.watch(deviceListProvider);
    final targetSerial = ref.watch(selectedTargetSerialProvider);
    _maybePromptForDeviceToolMode(devices.valueOrNull, targetSerial);
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
                        group.$1 == 'WORKSPACE' ? 'Workspace' :
                        group.$1 == 'APPLICATIONS' ? 'Applications' : 'Device Tools',
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
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth < 620 ? 12 : compact ? 16 : 28,
                      constraints.maxWidth < 620 ? 14 : compact ? 18 : 28,
                      constraints.maxWidth < 620 ? 12 : compact ? 16 : 28,
                      18,
                    ),
                    child: widget.child,
                  ),
                ),
                _buildOperationConsole(context, colors),
              ],
            ),
          ),
        ])),
      ])));
    });
  }
}
