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
  Future<void> _logWriteQueue = Future<void>.value();
  IOSink? _operationLogSink;
  int _operationLogBytes = 0;
  static const _maxOperationLogBytes = 5 * 1024 * 1024;
  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('WORKSPACE', [('Dashboard','/dashboard',Icons.grid_view_rounded),('Device Manager','/devices',Icons.devices_rounded)]),
    ('FIRMWARE', [('Firmware & Payload','/firmware',Icons.folder_open_rounded)]),
    ('DEVICE TOOLS', [('ADB Toolkit','/adb',Icons.terminal_rounded),('Fastboot Toolkit','/fastboot',Icons.memory_rounded)]),
    ('OBSERVABILITY', [('Logs & Diagnostics','/logs',Icons.receipt_long_rounded),('Operation History','/history',Icons.history_rounded)]),
  ];

  @override
  void initState() {
    super.initState();
    _deviceRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && ref.read(backendReadyProvider).hasValue) {
        ref.invalidate(deviceListProvider);
      }
    });

  }

  Future<void> _subscribeToBackendEvents(BackendClient client) async {
    if (identical(_eventClient, client)) return;
    await _events?.cancel();
    _eventClient = client;
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
      final timestamped = '${DateTime.now().toIso8601String()} $line';
      unawaited(_appendOperationLog(timestamped));
      setState(() {
        _consoleLines.add(timestamped);
        if (_consoleLines.length > 300) {
          _consoleLines.removeRange(0, _consoleLines.length - 300);
        }
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
    _logWriteQueue = _logWriteQueue.then((_) async {
      try {
        final file = File(_operationLogPath);
        await file.parent.create(recursive: true);
        final encoded = utf8.encode('$line\n');
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
    unawaited(_events?.cancel() ?? Future<void>.value());
    unawaited(_closeOperationLog());
    super.dispose();
  }

  Future<void> _closeOperationLog() async {
    try {
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
    final client = ref.watch(backendClientProvider);
    unawaited(_subscribeToBackendEvents(client));
    final backend = ref.watch(backendReadyProvider);
    final devices = ref.watch(deviceListProvider);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 1000;
      final expanded = _expanded && !compact;
      final colors = Theme.of(context).colorScheme;
      final surfaces = Theme.of(context).extension<DroidLabThemeSurfaces>();
      final deviceLabel = devices.when(
        data: (data) {
          final count = (data['devices'] as List<dynamic>? ?? const []).length;
          return count == 0 ? 'No device' : '$count device${count == 1 ? '' : 's'}';
        },
        error: (_, __) => 'Device scan error',
        loading: () => 'Scanning',
      );
      final backendLabel = backend.when(
        data: (_) => 'Backend online',
        error: (_, __) => 'Backend unavailable',
        loading: () => 'Backend starting',
      );
      return Scaffold(body: SafeArea(child: Column(children: [
        Container(height: 62, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: colors.surface, border: Border(bottom: BorderSide(color: colors.outlineVariant))),
          child: Row(children: [
            IconButton(tooltip: 'Toggle navigation', onPressed: () => setState(() => _expanded = !_expanded), icon: const Icon(Icons.menu)),
            Container(width: 34,height: 34,alignment: Alignment.center,decoration: BoxDecoration(color: colors.primary,borderRadius: BorderRadius.circular(9)),child: const Text('DL',style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white))),
            const SizedBox(width: 12),
            Text('DroidLab',style: Theme.of(context).textTheme.titleLarge),
            if (!compact) ...[const SizedBox(width: 12),Text('ANDROID ENGINEERING WORKSTATION',style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1))],
            const Spacer(),
            Chip(avatar: const Icon(Icons.usb,size: 14),label: Text(deviceLabel)),
            const SizedBox(width: 8),
            Chip(avatar: Icon(Icons.circle,size: 9,color: backend.hasValue ? Colors.green : colors.onSurfaceVariant),label: Text(backendLabel)),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Settings',onPressed: () => context.go('/settings'),icon: const Icon(Icons.settings_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Help',
              onSelected: (value) {
                if (value == 'about') context.go('/about');
                if (value == 'logs') context.go('/logs');
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'logs', child: Text('Debug tools / Open logs')),
                PopupMenuItem(value: 'about', child: Text('About DroidLab')),
              ],
              icon: const Icon(Icons.help_outline),
            ),
          ]),
        ),
        Expanded(child: Row(children: [
          AnimatedContainer(duration: const Duration(milliseconds: 160),width: expanded ? 232 : 68,color: colors.surface,
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 14),children: [
              for (final group in _groups) ...[
                if (expanded) Padding(padding: const EdgeInsets.fromLTRB(16,14,8,8),child: Text(group.$1,style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant,letterSpacing: 1))),
                for (final item in group.$2)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 2),
                    child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: Tooltip(message: item.$1,child: ListTile(
                      selected: widget.currentLocation == item.$2,
                      leading: Icon(item.$3),
                      title: expanded ? Text(item.$1,maxLines: 1,overflow: TextOverflow.ellipsis) : null,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: expanded ? 16 : 0,
                      ),
                      dense: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      onTap: () => context.go(item.$2),
                    )),
                  ),
                  ),
              ],
              const Divider(),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: expanded ? const Text('About DroidLab') : null,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: expanded ? 16 : 0,
                  ),
                  dense: true,
                  selected: widget.currentLocation == '/about',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  onTap: () => context.go('/about'),
                ),
              ),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: expanded ? const Text('Settings') : null,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: expanded ? 16 : 0,
                  ),
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  onTap: () => context.go('/settings'),
                ),
              ),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Padding(padding: EdgeInsets.all(compact ? 12 : 20),child: widget.child)),
        ])),
        if (_consoleVisible)
          Container(height: 132,decoration: BoxDecoration(color: surfaces?.console ?? colors.surface,border: Border(top: BorderSide(color: colors.outlineVariant))),
            child: Column(children: [
              ListTile(dense: true,leading: Icon(Icons.terminal,color: colors.primary),title: const Text('OPERATION CONSOLE'),trailing: Row(mainAxisSize: MainAxisSize.min,children: [
                IconButton(tooltip: 'Clear console',onPressed: () => setState(_consoleLines.clear),icon: const Icon(Icons.clear_all)),
                IconButton(tooltip: 'Hide console',onPressed: () => setState(() => _consoleVisible = false),icon: const Icon(Icons.keyboard_arrow_down)),
              ])),
              const Divider(height: 1),
              Expanded(child: _consoleLines.isEmpty
                ? const Padding(padding: EdgeInsets.all(12),child: Align(alignment: Alignment.topLeft,child: Text('Backend output and preflight events will stream here.',style: TextStyle(fontFamily: 'monospace'))))
                : ListView.builder(reverse: true,padding: const EdgeInsets.symmetric(horizontal: 12,vertical: 6),itemCount: _consoleLines.length,itemBuilder: (context,index) => Text(_consoleLines[_consoleLines.length-index-1],style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),maxLines: 2,overflow: TextOverflow.ellipsis)),
              ),
            ]),
          )
        else
          Align(alignment: Alignment.centerRight,child: TextButton.icon(onPressed: () => setState(() => _consoleVisible = true),icon: const Icon(Icons.terminal),label: const Text('Show console'))),
      ])));
    });
  }
}
