import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_settings.dart';
import '../state/backend_providers.dart';
import '../state/operation_history.dart';


Future<bool> _waitForDeviceTransport({
  required WidgetRef ref,
  required String serial,
  required String transport,
}) async {
  // USB disconnect/re-enumeration is asynchronous after reboot. Poll a bounded
  // number of times and only navigate once the same serial is visible again
  // on the expected transport.
  for (var attempt = 0; attempt < 10; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    ref.invalidate(deviceListProvider);
    try {
      final data = await ref.read(deviceListProvider.future);
      final devices = (data['devices'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      if (devices.any((device) =>
          device['serial'] == serial && device['transport'] == transport)) {
        return true;
      }
    } catch (_) {
      // The device may be temporarily absent while USB re-enumerates.
    }
  }
  return false;
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final devices = ref.watch(deviceListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1500;
    return _PageFrame(
      title: 'Dashboard',
      subtitle: 'Android engineering workstation overview.',
      child: GridView.count(
        crossAxisCount: wide ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: [
          _MetricCard(
            title: 'Backend',
            icon: Icons.hub,
            value: backend.when(
              data: (_) => 'Online',
              error: (_, __) => 'Unavailable',
              loading: () => 'Starting',
            ),
          ),
          _MetricCard(
            title: 'Connected devices',
            icon: Icons.devices,
            value: devices.when(
              data: (data) => ((data['devices'] as List<dynamic>? ?? const []).length).toString(),
              error: (_, __) => '—',
              loading: () => '…',
            ),
          ),
          const _MetricCard(title: 'Desktop', value: 'Ready', icon: Icons.desktop_windows),
        ],
      ),
    );
  }
}

class DeviceManagerPage extends ConsumerWidget {
  const DeviceManagerPage({super.key});

  Future<void> _showDeviceInfo(BuildContext context, WidgetRef ref, String serial) async {
    try {
      final result = await ref.read(backendClientProvider).request('device.info', {'serial': serial});
      if (!context.mounted) return;
      final metadata = result.data['metadata'] as Map<String, dynamic>;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Device details · $serial'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: metadata.entries.map((entry) => ListTile(
                dense: true,
                title: Text(entry.key),
                subtitle: SelectableText(
                  entry.value?.toString().isNotEmpty == true ? entry.value.toString() : '—',
                ),
              )).toList(),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read device details: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider);
    return _PageFrame(
      title: 'Device Manager',
      subtitle: 'Discover ADB and Fastboot targets. Multiple devices are never implicitly selected.',
      actions: [
        IconButton(
          onPressed: () => ref.invalidate(deviceListProvider),
          tooltip: 'Refresh devices',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPanel(
          message: error.toString(),
          retry: () => ref.invalidate(deviceListProvider),
        ),
        data: (data) {
          final list = (data['devices'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
          final warnings = data['warnings'] as List<dynamic>? ?? const [];
          if (list.isEmpty) {
            return Column(children: [
              const Expanded(
                child: _EmptyPanel(
                  icon: Icons.usb_off,
                  title: 'No Android devices detected',
                  message: 'Connect a device with USB debugging or Fastboot enabled.',
                ),
              ),
              for (final warning in warnings)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    warning['transport'].toString() + ': ' + warning['message'].toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ]);
          }
          return ListView.separated(
            itemCount: list.length + warnings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index >= list.length) {
                final warning = warnings[index - list.length];
                return ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(warning['transport'].toString() + ' discovery warning'),
                  subtitle: Text(warning['message'].toString()),
                );
              }
              final device = list[index];
              final transport = device['transport'] as String? ?? 'unknown';
              final state = device['state'] as String? ?? 'unknown';
              final serial = device['serial'] as String? ?? 'unknown';
              final product = device['product'] as String?;
              return Card(
                child: ListTile(
                  leading: Icon(transport == 'fastboot' ? Icons.memory : Icons.phone_android),
                  title: SelectableText(serial),
                  subtitle: Text(transport + ' · ' + state + (product == null ? '' : ' · ' + product)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Device details',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _showDeviceInfo(context, ref, serial),
                    ),
                    IconButton(
                      tooltip: 'Copy serial',
                      icon: const Icon(Icons.copy),
                      onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: serial))),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdbToolkitPage extends ConsumerStatefulWidget {
  const AdbToolkitPage({super.key});

  @override
  ConsumerState<AdbToolkitPage> createState() => _AdbToolkitPageState();
}

class _AdbToolkitPageState extends ConsumerState<AdbToolkitPage> {
  final _serial = TextEditingController();
  final _command = TextEditingController(text: 'getprop ro.build.version.release');
  final _package = TextEditingController();
  final _bugreport = TextEditingController();
  final _logcatFilters = TextEditingController();
  final _logSavePath = TextEditingController();
  final _logDisplayFilter = TextEditingController();
  final List<String> _logLines = [];
  IOSink? _logcatCaptureSink;
  String? _logcatCapturePath;
  List<String> _pausedLogSnapshot = [];
  bool _logPaused = false;
  StreamSubscription<BackendEvent>? _eventSubscription;
  String? _logcatRequestId;
  String? _logcatManualStopRequestId;
  String _output = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventSubscription = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'logcat' && mounted) {
        try {
          _logcatCaptureSink?.writeln(event.line);
        } catch (_) {
          // A stop/dispose may close the file sink while the last event is in flight.
        }
        setState(() {
          _logLines.add(event.line);
          if (_logLines.length > 500) {
            _logLines.removeRange(0, _logLines.length - 500);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    final logcatRequestId = _logcatRequestId;
    if (logcatRequestId != null) {
        unawaited(ref.read(backendClientProvider).cancel(logcatRequestId));
    }
    unawaited(_closeLogcatCapture());
    unawaited(_eventSubscription?.cancel() ?? Future<void>.value());
    _serial.dispose();
    _command.dispose();
    _package.dispose();
    _bugreport.dispose();
    _logcatFilters.dispose();
    _logSavePath.dispose();
    _logDisplayFilter.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    ref.invalidate(deviceListProvider);
    try {
      await ref.read(deviceListProvider.future);
      if (mounted) setState(() => _output = 'Device scan completed. Select an ADB or Fastboot target below.');
    } catch (error) {
      if (mounted) setState(() => _output = 'Device scan failed: $error');
    }
  }

  Map<String, dynamic>? _selectedDevice() {
    final data = ref.read(deviceListProvider).valueOrNull;
    final devices = (data?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final device in devices) {
      if (device['serial'] == _serial.text.trim()) return device;
    }
    return null;
  }

  String? _stripHostExecutable(String command, String executable) {
    final pattern = RegExp(
      '^' + RegExp.escape(executable) + r'(?:\.exe)?(?:\s+|$)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(command.trimLeft());
    if (match == null) return null;
    return command.trimLeft().substring(match.end).trim();
  }

  Future<bool> _confirmCommand({
    required String title,
    required String target,
    required String command,
    required String warning,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + target),
            const SizedBox(height: 8),
            SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            Text(warning),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Execute command')),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _runShell() async {
    final command = _command.text.trim();
    if (command.isEmpty || _busy) return;

    final target = _selectedDevice();
    final serial = target?['serial'] as String?;
    final transport = target?['transport'] as String?;
    final state = target?['state'] as String?;

    final fastbootArguments = _stripHostExecutable(command, 'fastboot');
    if (fastbootArguments != null) {
      final verb = fastbootArguments.split(RegExp(r'\\s+')).first.toLowerCase();
      const discovery = {'devices', 'help', '--help', '--version', 'version'};
      final isDiscovery = discovery.contains(verb);
      if (!isDiscovery && (transport != 'fastboot' || serial == null || state != 'fastboot')) {
        setState(() => _output =
            'Select a detected Fastboot device before running a device-targeted Fastboot command. Discovery commands such as fastboot devices do not need a selected device.');
        return;
      }
      if (fastbootArguments.isEmpty) {
        setState(() => _output = 'Enter Fastboot arguments, for example: devices or getvar all.');
        return;
      }
      final fastbootTarget = isDiscovery ? null : serial;
      final fastbootPreview = 'fastboot ' +
          (fastbootTarget == null ? '' : '-s $fastbootTarget ') +
          fastbootArguments;
      final confirmed = await _confirmCommand(
        title: 'Confirm advanced Fastboot command',
        target: fastbootTarget ?? 'host / discovery command',
        command: fastbootPreview,
        warning: isDiscovery
            ? 'This runs a host-side Fastboot discovery/help command and does not target a device.'
            : 'Advanced Fastboot commands can change boot state, erase data, or make the device unbootable. Verify the exact command and device.',
      );
      if (!confirmed) return;
      setState(() => _busy = true);
      try {
        final result = await trackOperation(
          ref,
          operation: 'Advanced Fastboot: ' + fastbootArguments,
          target: fastbootTarget ?? 'host',
          action: () => ref.read(backendClientProvider).request('fastboot.command', {
            'serial': fastbootTarget,
            'command': fastbootArguments,
            'confirmed': true,
            'confirmation': {
              'operation': 'fastboot.command',
              'serial': fastbootTarget,
              'command': fastbootArguments,
            },
          }, timeout: const Duration(minutes: 30)),
        );
        if (mounted) setState(() => _output = result.data['output']?.toString() ??
            result.data.toString());
      } catch (error) {
        if (mounted) setState(() => _output = error.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final adbArguments = _stripHostExecutable(command, 'adb');
    if (adbArguments != null) {
      final args = adbArguments.isEmpty ? 'devices -l' : adbArguments;
      final verb = args.split(RegExp(r'\s+')).first.toLowerCase();
      if (verb == 'reboot') {
        final tokens = args.split(RegExp(r'\s+'));
        final mode = tokens.length > 1 ? tokens[1].toLowerCase() : 'system';
        if (mode == 'recovery' || mode == 'bootloader' || mode == 'system' || mode == 'fastboot') {
          await _reboot(mode);
        } else {
          if (mounted) setState(() => _output =
              'Use reboot, reboot recovery, reboot bootloader, or reboot fastboot.');
        }
        return;
      }
      final selectedAdbSerial = transport == 'adb' ? serial : null;
      final confirmed = await _confirmCommand(
        title: 'Confirm advanced host ADB command',
        target: selectedAdbSerial ?? 'host / discovery command',
        command: 'adb ' + args,
        warning:
            'Host ADB commands are unrestricted. They may install packages, transfer files, modify the selected device, or affect the local ADB server.',
      );
      if (!confirmed) return;
      setState(() => _busy = true);
      try {
        final result = await trackOperation(
          ref,
          operation: 'Advanced ADB: ' + args,
          target: selectedAdbSerial ?? 'host',
          action: () => ref.read(backendClientProvider).request('adb.command', {
            'serial': selectedAdbSerial,
            'command_text': args,
            'confirmed': true,
            'confirmation': {
              'operation': 'adb.command',
              'serial': selectedAdbSerial,
              'command_text': args,
            },
          }, timeout: const Duration(minutes: 30)),
        );
        if (mounted) setState(() => _output = result.data['output']?.toString() ??
            result.data.toString());
      } catch (error) {
        if (mounted) setState(() => _output = error.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    if (transport != 'adb' || state != 'device' || serial == null) {
      setState(() => _output =
          'Select an authorized ADB device for Android shell commands. Host commands must start with adb; Fastboot commands must start with fastboot.');
      return;
    }
    final potentiallyDestructive = RegExp(
      r'(^|[;&|]\s*)(rm\s+-.*r|mkfs(\.[\w-]+)?|dd\s|reboot\\b|poweroff\\b|shutdown\\b|setprop\\b|pm\s+(uninstall|disable-user)\\b|svc\b.*\bdisable\\b|wipe\\b|format\\b)',
      caseSensitive: false,
    ).hasMatch(command);
    final confirmed = await _confirmCommand(
      title: potentiallyDestructive
          ? 'Potentially destructive device-shell command'
          : 'Confirm Android shell command',
      target: serial,
      command: 'adb -s $serial shell $command',
      warning: potentiallyDestructive
          ? 'This command may modify system state or remove data. Review it carefully before execution.'
          : 'Review the exact device target and command before dispatch.',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB shell',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.shell', {
          'serial': serial,
          'command_text': command,
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.shell',
            'serial': serial,
            'command_text': command,
          },
        }),
      );
      if (mounted) {
        setState(() => _output = result.data['output'] as String? ?? 'Command completed.');
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reboot(String mode) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm device reboot'),
        content: Text('Send a reboot request to ' + serial + ' into ' + mode + ' mode?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB reboot (' + mode + ')',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.reboot', {
          'serial': serial,
          'mode': mode,
          'confirmed': true,
          'confirmation': {'operation': 'adb.reboot', 'serial': serial, 'mode': mode},
        }),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && (mode == 'bootloader' || mode == 'fastboot')) {
        final transitioned = await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'fastboot',
        );
        if (mounted && transitioned) context.go('/fastboot');
      } else if (mounted) {
        // Recovery and normal Android boot remain on the ADB workspace.
        await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'adb',
        );
      }
    }
  }

  Future<void> _closeLogcatCapture() async {
    final sink = _logcatCaptureSink;
    final path = _logcatCapturePath;
    _logcatCaptureSink = null;
    _logcatCapturePath = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Preserve the operation result even if the destination becomes unavailable.
    }
    if (mounted && path != null) {
      setState(() => _output = 'Full logcat stream saved to $path');
    }
  }

  Future<void> _captureLogcatToFile() async {
    final device = _selectedDevice();
    if (_logcatRequestId != null || _busy) return;
    if (device == null || device['transport'] != 'adb' || device['state'] != 'device') {
      setState(() => _output = 'Select an authorized online ADB device before capturing logcat.');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logcat.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Logcat text', extensions: ['txt', 'log']),
      ],
    );
    if (location == null || !mounted) return;
    try {
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
      sink.writeln('DroidLab logcat capture');
      sink.writeln('Device: ${_serial.text.trim()}');
      sink.writeln('Started: ${DateTime.now().toIso8601String()}');
      sink.writeln('Capture window: 1 hour maximum');
      sink.writeln();
      _logcatCaptureSink = sink;
      _logcatCapturePath = file.path;
      await _startLogcat(captureToFile: true);
    } catch (error) {
      await _closeLogcatCapture();
      if (mounted) {
        setState(() => _output = 'Could not start logcat file capture: $error');
      }
    }
  }

  Future<void> _startLogcat({bool captureToFile = false}) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _logcatRequestId != null) return;
    final filters = _logcatFilters.text.trim().isEmpty
        ? <String>[]
        : _logcatFilters.text.trim().split(RegExp(r'\s+'));
    try {
      final handle = await ref.read(backendClientProvider).startOperation(
        'adb.logcat.start',
        {
          'serial': serial,
          'filters': filters,
          if (captureToFile) 'timeout_seconds': 3600,
        },
      );
      if (!mounted) {
        await ref.read(backendClientProvider).cancel(handle.requestId);
        await _closeLogcatCapture();
        return;
      }
      final capturePathForRequest = captureToFile ? _logcatCapturePath : null;
      setState(() {
        _logcatRequestId = handle.requestId;
        _logLines.clear();
        _pausedLogSnapshot = [];
        _logPaused = false;
      });
      unawaited(trackOperation(
        ref,
        operation: captureToFile ? 'ADB logcat file capture (1 hour)' : 'ADB logcat',
        target: serial,
        action: () => handle.result,
        successSummary: (result) => result.data['duration_limit_reached'] == true
            ? 'One-hour logcat capture completed.'
            : 'Logcat stream stopped.',
      ).then((result) async {
        final manuallyStopped = _logcatManualStopRequestId == handle.requestId;
        if (manuallyStopped) _logcatManualStopRequestId = null;
        await _closeLogcatCapture();
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = manuallyStopped
                ? capturePathForRequest != null
                    ? 'Logcat capture stopped and saved to $capturePathForRequest'
                    : 'Logcat stream stopped.'
                : result.data['duration_limit_reached'] == true
                    ? 'One-hour logcat capture completed.'
                    : result.data.toString();
          });
        }
      }, onError: (Object error) async {
        final manuallyStopped = _logcatManualStopRequestId == handle.requestId;
        if (manuallyStopped) _logcatManualStopRequestId = null;
        await _closeLogcatCapture();
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = manuallyStopped
                ? capturePathForRequest != null
                    ? 'Logcat capture stopped and saved to $capturePathForRequest'
                    : 'Logcat stream stopped.'
                : error.toString();
          });
        }
      }));
    } catch (error) {
      await _closeLogcatCapture();
      if (mounted) setState(() => _output = error.toString());
    }
  }

  Future<void> _stopLogcat() async {
    final id = _logcatRequestId;
    if (id == null) return;
    _logcatManualStopRequestId = id;
    final capturePath = _logcatCapturePath;
    try {
      await ref.read(backendClientProvider).cancel(id);
    } catch (error) {
      if (mounted) setState(() => _output = 'Could not stop logcat cleanly: $error');
    }
    await _closeLogcatCapture();
    if (mounted) {
      setState(() {
        _logcatRequestId = null;
        _output = capturePath != null
            ? 'Logcat capture stopped and saved to $capturePath'
            : 'Logcat stream stopped.';
      });
    }
  }

  Future<void> _browseSideloadPackage() async {
    const group = XTypeGroup(label: 'Recovery OTA ZIP', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _package.text = file.path);
  }

  Future<void> _sideload() async {
    final serial = _serial.text.trim();
    final packagePath = _package.text.trim();
    if (serial.isEmpty || packagePath.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm recovery sideload'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            Text('OTA package: ' + packagePath),
            const SizedBox(height: 12),
            const Text('Recovery sideload may update device partitions. A successful host exit does not prove Android accepted the update.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sideload')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB recovery sideload',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.sideload', {
          'serial': serial,
          'package_path': packagePath,
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.sideload',
            'serial': serial,
            'package_path': packagePath,
          },
        }, timeout: const Duration(minutes: 35)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBugreport() async {
    final serial = _serial.text.trim();
    final outputPath = _bugreport.text.trim();
    if (serial.isEmpty || outputPath.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate device bugreport?'),
        content: Text(
          'The bugreport for ' + serial +
          ' can contain account, network, location and application diagnostics. Save it only to a location you control and review it before sharing.\n\nOutput: ' +
          outputPath,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate report')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB bugreport',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.bugreport', {
          'serial': serial,
          'output_path': outputPath,
        }, timeout: const Duration(minutes: 20)),
        successSummary: (result) => 'Report saved to ' + (result.data['path']?.toString() ?? outputPath),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDeviceInfo() async {
    final serial = _serial.text.trim();
    final target = _selectedDevice();
    if (serial.isEmpty || target == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'device.info',
        {'serial': serial},
      );
      if (mounted) {
        final metadata = result.data['metadata'] as Map<String, dynamic>? ?? const {};
        setState(() {
          _output = metadata.entries
              .map((entry) => entry.key + ': ' +
                  (entry.value?.toString().isNotEmpty == true
                      ? entry.value.toString()
                      : '—'))
              .join('\\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browseLogSavePath() async {
    const group = XTypeGroup(label: 'Logcat text', extensions: ['txt', 'log']);
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logcat.txt',
      acceptedTypeGroups: [group],
    );
    if (location != null && mounted) {
      setState(() => _logSavePath.text = location.path);
    }
  }

  Future<void> _browseBugreportOutput() async {
    const group = XTypeGroup(label: 'Bugreport ZIP', extensions: ['zip']);
    final location = await getSaveLocation(
      suggestedName: 'bugreport.zip',
      acceptedTypeGroups: [group],
    );
    if (location != null && mounted) {
      setState(() => _bugreport.text = location.path);
    }
  }

  Future<void> _saveLogcat() async {
    final path = _logSavePath.text.trim();
    if (path.isEmpty || _logLines.isEmpty) return;
    try {
      final file = File(path).absolute;
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      await file.writeAsString(_logLines.join('\n'), mode: FileMode.writeOnly);
      if (mounted) {
        setState(() => _output = 'Saved ' + _logLines.length.toString() + ' logcat lines to ' + file.path);
      }
    } catch (error) {
      if (mounted) setState(() => _output = 'Could not save logcat: ' + error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceListProvider);
    final discoveredDevices = (devicesAsync.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final selectedDevices = discoveredDevices
        .where((device) => device['serial'] == _serial.text.trim())
        .toList();
    final selectedDevice = selectedDevices.isEmpty ? null : selectedDevices.first;
    final selectedTransport = selectedDevice?['transport'] as String?;
    final Object? selectedState =
        selectedDevice == null ? null : selectedDevice['state'];
    final String? selectedAdbState = selectedTransport == 'adb'
        ? selectedState as String?
        : null;
    final selectedFastboot = selectedTransport == 'fastboot' &&
        selectedDevice?['state'] == 'fastboot';
    final canRunAdbCommands = selectedAdbState == 'device';
    final canReboot = canRunAdbCommands ||
        selectedAdbState == 'recovery' || selectedFastboot;
    return _PageFrame(
    title: 'ADB Toolkit',
    subtitle: 'Select an authorized ADB device for shell and diagnostics. Reboot also supports devices already in Fastboot.',
    child: ListView(children: [
      Row(children: [
        Expanded(child: _TextField(controller: _serial, label: 'Device serial')),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Refresh connected devices',
          onPressed: _busy ? null : _refreshDevices,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      const SizedBox(height: 8),
      devicesAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Row(children: [
          Expanded(child: Text('Device scan failed: $error')),
          TextButton(onPressed: _refreshDevices, child: const Text('Retry')),
        ]),
        data: (data) {
          final devices = (data['devices'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
          final warnings = (data['warnings'] as List<dynamic>? ?? const [])
              .where((warning) => warning is Map)
              .toList();
          final serials = devices.map((device) => device['serial'] as String).toSet();
          final selected = serials.contains(_serial.text.trim()) ? _serial.text.trim() : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Detected ADB / Fastboot devices',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select a device explicitly'),
              items: devices.map((device) {
                final serial = device['serial'] as String;
                final state = device['state'] as String? ?? 'unknown';
                final transport = device['transport'] as String? ?? 'unknown';
                return DropdownMenuItem<String>(
                  value: serial,
                  child: Text('$serial  ·  $transport: $state', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _serial.text = value);
              },
            ),
            for (final device in devices.where((item) => item['serial'] == selected))
              if (device['transport'] == 'adb' && device['state'] == 'unauthorized')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'ADB authorization required: unlock the Android device and accept its USB debugging RSA prompt, then refresh devices.',
                    style: TextStyle(color: Colors.orange),
                  ),
                )
              else if (device['transport'] == 'adb' && device['state'] == 'offline')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Device is offline. Reconnect the USB cable or restart ADB, then refresh devices.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  warning['message'].toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (devices.isEmpty && warnings.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('No ADB or Fastboot devices found. Connect a device and refresh.'),
              ),
          ]);
        },
      ),
      if (selectedAdbState != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            selectedAdbState == 'device'
                ? 'ADB authorized · commands are enabled for this selected device.'
                : selectedAdbState == 'recovery' || selectedAdbState == 'sideload'
                    ? 'Recovery transport · only recovery-supported ADB operations are available.'
                    : 'ADB $selectedAdbState · authorize or reconnect the device before running commands.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: canRunAdbCommands
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      const SizedBox(height: 12),
      _TextField(controller: _command, label: 'Command', hint: 'dumpsys battery · adb devices -l · fastboot getvar all'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy || !canRunAdbCommands ? null : _runShell, child: const Text('Run shell command')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('system'), child: const Text('Reboot')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('bootloader'), child: const Text('Bootloader')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('recovery'), child: const Text('Recovery')),
        FilledButton.tonal(onPressed: _busy || !canReboot ? null : () => _reboot('fastboot'), child: const Text('Fastbootd')),
        OutlinedButton(onPressed: _busy || !(canRunAdbCommands || selectedFastboot) ? null : _loadDeviceInfo, child: const Text('Device info')),
        OutlinedButton(
          onPressed: _logcatRequestId != null ? _stopLogcat : (canRunAdbCommands ? _startLogcat : null),
          child: Text(_logcatRequestId == null ? 'Start logcat' : 'Stop logcat'),
        ),
      ]),
      const SizedBox(height: 14),
      _TextField(controller: _logcatFilters, label: 'Logcat filters (optional)', hint: '*:W or ActivityManager:I'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _TextField(controller: _logSavePath, label: 'Logcat save path')),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _browseLogSavePath, child: const Text('Browse…')),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(onPressed: _saveLogcat, child: const Text('Save captured buffer')),
        OutlinedButton(
          onPressed: _logcatRequestId == null && !_busy && canRunAdbCommands ? _captureLogcatToFile : null,
          child: const Text('Capture full logcat to file (1 hour)'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: DropTarget(
          onDragDone: (detail) {
            if (detail.files.isNotEmpty) setState(() => _package.text = detail.files.first.path);
          },
          child: _TextField(controller: _package, label: 'Recovery OTA ZIP path'),
        )),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _browseSideloadPackage, child: const Text('Browse ZIP…')),
      ]),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy || !(selectedAdbState == 'device' || selectedAdbState == 'recovery' || selectedAdbState == 'sideload') ? null : _sideload,
        child: const Text('Sideload OTA'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _TextField(controller: _bugreport, label: 'Bugreport output ZIP path')),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _browseBugreportOutput, child: const Text('Browse…')),
      ]),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _busy || !canRunAdbCommands ? null : _createBugreport, child: const Text('Generate bugreport')),
      const SizedBox(height: 18),
      if (_busy) const LinearProgressIndicator(),
      _OutputPanel(output: _output.isEmpty ? 'Command output appears here.' : _output),
      if (_logcatRequestId != null || _logLines.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('LIVE LOGCAT', style: Theme.of(context).textTheme.labelLarge)),
          OutlinedButton(
            onPressed: () => setState(() {
              if (!_logPaused) {
                _pausedLogSnapshot = List<String>.of(_logLines);
                _logPaused = true;
              } else {
                _logPaused = false;
                _pausedLogSnapshot = [];
              }
            }),
            child: Text(_logPaused ? 'Resume display' : 'Pause display'),
          ),
        ]),
        const SizedBox(height: 8),
        _TextField(
          controller: _logDisplayFilter,
          label: 'Filter visible log lines',
          hint: 'Case-insensitive text filter',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        _OutputPanel(output: (() {
          final source = _logPaused ? _pausedLogSnapshot : _logLines;
          final needle = _logDisplayFilter.text.trim().toLowerCase();
          final visible = source.where((line) => needle.isEmpty || line.toLowerCase().contains(needle));
          return visible.join('\n');
        })()),
        if (_logPaused)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Display paused. Incoming lines continue to be buffered.', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ]),
  );
  }
}

class FastbootToolkitPage extends ConsumerStatefulWidget {
  const FastbootToolkitPage({super.key});

  @override
  ConsumerState<FastbootToolkitPage> createState() => _FastbootToolkitPageState();
}

class _FastbootToolkitPageState extends ConsumerState<FastbootToolkitPage> {
  final _serial = TextEditingController();
  final _partition = TextEditingController();
  final _image = TextEditingController();
  final _advancedCommand = TextEditingController(text: 'getvar all');
  String? _selectedSerial;
  String _advancedPreview = '';
  String _output = '';
  bool _busy = false;
  List<Map<String, dynamic>> _discoveredPartitions = [];

  @override
  void dispose() {
    _serial.dispose();
    _partition.dispose();
    _image.dispose();
    _advancedCommand.dispose();
    super.dispose();
  }

  Future<void> _browseFastbootImage() async {
    const group = XTypeGroup(label: 'Android partition image', extensions: ['img']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    final name = file.name.toLowerCase();
    const partitions = {
      'boot.img': 'boot',
      'vendor.img': 'vendor',
      'vendor_boot.img': 'vendor_boot',
      'init_boot.img': 'init_boot',
      'dtbo.img': 'dtbo',
      'vbmeta.img': 'vbmeta',
      'recovery.img': 'recovery',
      'system.img': 'system',
      'product.img': 'product',
      'odm.img': 'odm',
      'system_ext.img': 'system_ext',
      'vbmeta_system.img': 'vbmeta_system',
      'vbmeta_vendor.img': 'vbmeta_vendor',
    };
    setState(() {
      _image.text = file.path;
      _partition.text = partitions[name] ?? _partition.text;
    });
  }

  void _acceptImageDrop(DropDoneDetails detail) {
    if (detail.files.isEmpty) return;
    final file = detail.files.first;
    setState(() {
      _image.text = file.path;
      if (_partition.text.trim().isEmpty) {
        final name = file.name;
        _partition.text = name.toLowerCase().endsWith('.img')
            ? name.substring(0, name.length - 4)
            : name;
      }
    });
  }

  Future<void> _mutate(String operation) async {
    final serial = _serial.text.trim();
    final partition = _partition.text.trim();
    final image = _image.text.trim();
    if (serial.isEmpty || partition.isEmpty ||
        (operation == 'fastboot.flash' && image.isEmpty) || _busy) return;

    final command = operation == 'fastboot.flash'
        ? 'fastboot -s ' + serial + ' flash ' + partition + ' ' + image
        : 'fastboot -s ' + serial + ' erase ' + partition;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(operation == 'fastboot.flash' ? 'Confirm partition flash' : 'Confirm partition erase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            Text('Partition: ' + partition),
            if (operation == 'fastboot.flash') Text('Image: ' + image),
            const SizedBox(height: 12),
            const Text('This operation modifies device partitions and may make the device unbootable.'),
            const SizedBox(height: 12),
            SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I understand — execute')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final args = <String, dynamic>{
        'serial': serial,
        'partition': partition,
        'confirmed': true,
        'confirmation': operation == 'fastboot.flash'
            ? {
                'operation': 'fastboot.flash',
                'serial': serial,
                'partition': partition,
                'image_path': image,
              }
            : {
                'operation': 'fastboot.erase',
                'serial': serial,
                'partition': partition,
              },
      };
      if (operation == 'fastboot.flash') args['image_path'] = image;
      final result = await trackOperation(
        ref,
        operation: operation == 'fastboot.flash'
            ? 'Fastboot flash ' + partition
            : 'Fastboot erase ' + partition,
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          operation,
          args,
          timeout: const Duration(minutes: 20),
        ),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebootFastboot(String mode) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final label = mode == 'system' ? 'Android' : mode == 'fastbootd' ? 'Fastbootd (userspace Fastboot)' : mode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Fastboot reboot'),
        content: Text('Reboot Fastboot target ' + serial + ' to ' + label + '?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Fastboot reboot (' + mode + ')',
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          'fastboot.reboot',
          {
            'serial': serial,
            'mode': mode,
            'confirmed': true,
            'confirmation': {'operation': 'fastboot.reboot', 'serial': serial, 'mode': mode},
          },
        ),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && mode == 'system') {
        final transitioned = await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'adb',
        );
        if (mounted && transitioned) context.go('/adb');
      } else if (mounted) {
        await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'fastboot',
        );
      }
    }
  }

  bool _isFastbootDiscoveryCommand(String command) {
    final verb = command.trim().split(RegExp(r'\s+')).first.toLowerCase();
    return const {'devices', 'help', '--help', '--version', 'version'}.contains(verb);
  }

  String _fastbootCommandPreview(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    if (_isFastbootDiscoveryCommand(trimmed) || _serial.text.trim().isEmpty) {
      return 'fastboot ' + trimmed;
    }
    return 'fastboot -s ' + _serial.text.trim() + ' ' + trimmed;
  }

  Future<void> _runAdvancedCommand() async {
    final serial = _serial.text.trim();
    final command = _advancedCommand.text.trim();
    if (command.isEmpty || _busy) return;
    final discovery = _isFastbootDiscoveryCommand(command);
    if (!discovery && serial.isEmpty) {
      setState(() => _output = 'Select a Fastboot device for device-targeted commands. Discovery/help/version commands do not require a target.');
      return;
    }
    final target = discovery ? null : serial;
    final preview = _fastbootCommandPreview(command);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm advanced Fastboot command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + (target ?? 'host / discovery command')),
            const SizedBox(height: 8),
            Text(discovery
                ? 'This is a host-side Fastboot discovery/help command and does not mutate a selected device.'
                : 'Advanced commands are unrestricted and may erase data, change boot state, or make the device unbootable. Review the exact command.'),
            const SizedBox(height: 12),
            SelectableText(preview, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: discovery
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Execute command'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Advanced Fastboot: ' + command,
        target: target ?? 'host',
        action: () => ref.read(backendClientProvider).request('fastboot.command', {
          'serial': target,
          'command': command,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.command',
            'serial': target,
            'command': command,
          },
        }, timeout: const Duration(minutes: 30)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discoverPartitions() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Discover Fastboot partitions',
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          'fastboot.partitions',
          {'serial': serial},
        ),
      );
      final partitions = (result.data['partitions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (mounted) {
        setState(() {
          _discoveredPartitions = partitions;
          _output = partitions.map((item) {
            final details = [
              if (item['size'] != null) 'size: ${item['size']}',
              if (item['type'] != null) 'type: ${item['type']}',
              if (item['has_slot'] != null) 'slot: ${item['has_slot']}',
              if (item['is_logical'] != null) 'logical: ${item['is_logical']}',
            ].join(', ');
            return '${item['name']}${details.isEmpty ? '' : ' — $details'}';
          }).join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readFastbootInfo(String serial) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'device.info',
        {'serial': serial},
      );
      if (mounted) {
        final metadata = result.data['metadata'] as Map<String, dynamic>;
        setState(() {
          _output = metadata.entries
              .map((entry) => entry.key + ': ' +
                  (entry.value?.toString().isNotEmpty == true
                      ? entry.value.toString()
                      : '—'))
              .join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActiveSlot(String slot) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy || !const {'a', 'b', 'other'}.contains(slot)) return;
    final command = 'fastboot -s $serial --set-active=$slot';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(slot == 'other' ? 'Switch to the other active slot?' : 'Set active slot ${slot.toUpperCase()}?'),
        content: Text(
          slot == 'other'
              ? 'Ask the bootloader to select the slot opposite the currently active slot on $serial. The bootloader resolves "other"; verify the resulting current-slot before rebooting. This can make the device fail to start if that slot is incomplete.\n\nfastboot -s $serial set_active other'
              : 'Change the active boot slot on $serial. This affects the next boot and can make the device fail to start if the selected slot is incomplete.\n\n$command',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change active slot'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: slot == 'other' ? 'Fastboot switch to other active slot' : 'Fastboot set active slot ${slot.toUpperCase()}',
        target: serial,
        action: () => ref.read(backendClientProvider).request('fastboot.set_active', {
          'serial': serial,
          'slot': slot,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.set_active',
            'serial': serial,
            'slot': slot,
          },
        }),
      );
      if (mounted) setState(() => _output = result.data.toString());
      ref.invalidate(deviceListProvider);
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipeUserdata() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm factory data wipe'),
        content: Text(
          'fastboot -w will erase userdata and cache on ' + serial +
          '. This permanently removes local data. Confirm only after verifying your backup and target.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase all user data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Fastboot wipe userdata and cache',
        target: serial,
        action: () => ref.read(backendClientProvider).request('fastboot.wipe', {
          'serial': serial,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.wipe',
            'serial': serial,
            'mode': 'wipe-userdata',
          },
        }, timeout: const Duration(minutes: 12)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceListProvider);
    final devices = (devicesAsync.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((device) => device['transport'] == 'fastboot')
        .toList();
    final serials = devices.map((device) => device['serial'] as String).toList();
    final selectedSerial = serials.contains(_selectedSerial) ? _selectedSerial : null;
    if (selectedSerial != null && selectedSerial != _serial.text && !_busy) {
      _serial.text = selectedSerial;
    }
    return _PageFrame(
    title: 'Fastboot Toolkit',
    subtitle: 'Destructive actions require fresh target validation and an explicit confirmation.',
    child: ListView(children: [
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: selectedSerial,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Detected Fastboot devices',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select a Fastboot device'),
          items: devices.map((device) => DropdownMenuItem<String>(
            value: device['serial'] as String,
            child: Text(device['serial'] as String, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (value) => setState(() {
            _selectedSerial = value;
            _serial.text = value ?? '';
          }),
        )),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Refresh devices',
          onPressed: _busy ? null : () => ref.invalidate(deviceListProvider),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      if (devicesAsync.hasError) Text('Device scan failed: ${devicesAsync.error}'),
      if (devices.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No Fastboot device detected. Switch the phone to bootloader mode, then refresh.'),
        ),
      const SizedBox(height: 12),
      if (_discoveredPartitions.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: _discoveredPartitions.any((item) => item['name'] == _partition.text)
              ? _partition.text
              : null,
          decoration: const InputDecoration(
            labelText: 'Discovered partitions',
            border: OutlineInputBorder(),
          ),
          items: _discoveredPartitions.map((item) {
            final name = item['name'] as String;
            final size = item['size']?.toString();
            return DropdownMenuItem<String>(
              value: name,
              child: Text(size == null ? name : '$name · $size'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _partition.text = value);
          },
        ),
      _TextField(controller: _partition, label: 'Partition name', hint: 'boot_a'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropTarget(
          onDragDone: _acceptImageDrop,
          child: _TextField(controller: _image, label: 'Image path', hint: 'Drop a partition .img or enter its path'),
        )),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _browseFastbootImage, child: const Text('Browse image…')),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _busy || selectedSerial == null ? null : _discoverPartitions,
          icon: const Icon(Icons.list_alt),
          label: const Text('Discover partitions'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || selectedSerial == null ? null : () => _readFastbootInfo(selectedSerial),
          icon: const Icon(Icons.info_outline),
          label: const Text('Device info'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _mutate('fastboot.flash'),
          icon: const Icon(Icons.flash_on),
          label: const Text('Flash image'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _mutate('fastboot.erase'),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Erase selected partition'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('system'),
          child: const Text('Reboot system'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('recovery'),
          child: const Text('Reboot recovery'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('bootloader'),
          child: const Text('Reboot bootloader'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : () => _rebootFastboot('fastbootd'),
          child: const Text('Reboot to Fastbootd'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('ERASE & FORMAT', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: _busy ? null : () {
            _partition.text = 'cache';
            _mutate('fastboot.erase');
          },
          child: const Text('Erase cache'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () {
            _partition.text = 'userdata';
            _mutate('fastboot.erase');
          },
          child: const Text('Erase userdata'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : _wipeUserdata,
          child: const Text('Wipe data (fastboot -w)'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('BOOT SLOT', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton(
          onPressed: _busy ? null : () => _setActiveSlot('a'),
          child: const Text('Set active slot A'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _setActiveSlot('b'),
          child: const Text('Set active slot B'),
        ),
        FilledButton.tonal(
          onPressed: _busy || selectedSerial == null ? null : () => _setActiveSlot('other'),
          child: const Text('Switch to other slot'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('ADVANCED FASTBOOT COMMAND', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _TextField(
        controller: _advancedCommand,
        label: 'Fastboot arguments',
        hint: 'getvar all · flashing get_unlock_ability',
        onChanged: (value) => setState(() {
          _advancedPreview = _fastbootCommandPreview(value);
        }),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: () => setState(() {
            _advancedPreview = _fastbootCommandPreview(_advancedCommand.text);
          }),
          child: const Text('Preview command'),
        ),
        FilledButton(
          onPressed: _busy ? null : _runAdvancedCommand,
          child: const Text('Run command'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _advancedCommand.clear();
            _advancedPreview = '';
          }),
          child: const Text('Clear command'),
        ),
      ]),
      if (_advancedPreview.isNotEmpty)
        SelectableText(_advancedPreview, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      const SizedBox(height: 18),
      if (_busy) const LinearProgressIndicator(),
      _OutputPanel(output: _output.isEmpty ? 'Fastboot operation results appear here.' : _output),
    ]),
  );
  }
}

class PayloadExtractorPage extends ConsumerStatefulWidget {
  const PayloadExtractorPage({super.key});

  @override
  ConsumerState<PayloadExtractorPage> createState() => _PayloadExtractorPageState();
}

class _PayloadExtractorPageState extends ConsumerState<PayloadExtractorPage> {
  final _source = TextEditingController();
  final _output = TextEditingController();
  final _partitionFilter = TextEditingController();
  final Set<String> _selected = {};
  final List<String> _activityLines = [];
  final List<({String label, String path})> _mountedLocations = [];
  String? _selectedMount;
  StreamSubscription<BackendEvent>? _events;
  List<Map<String, dynamic>> _parts = [];
  String _status = 'Drop an OTA ZIP or payload BIN file here, or enter its path.';
  bool _busy = false;
  bool _sha = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    _output.text = '$home${Platform.pathSeparator}DroidLab';
    _events = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'payload' && mounted) {
        final match = RegExp(r'(\d{1,3})%').firstMatch(event.line);
        final percent = match == null ? null : int.tryParse(match.group(1)!);
        setState(() {
          _activityLines.add(event.line);
          if (percent != null && percent >= 0 && percent <= 100) {
            _progress = percent / 100;
          }
          if (_activityLines.length > 300) {
            _activityLines.removeRange(0, _activityLines.length - 300);
          }
        });
      }
    });
    unawaited(_refreshMountedLocations());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel() ?? Future<void>.value());
    _source.dispose();
    _output.dispose();
    _partitionFilter.dispose();
    super.dispose();
  }

  Future<void> _browseSource() async {
    const group = XTypeGroup(label: 'OTA and payload files', extensions: ['zip', 'bin']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _source.text = file.path);
  }

  Future<void> _browseOutput() async {
    final directory = await getDirectoryPath(confirmButtonText: 'Use output directory');
    if (directory != null && mounted) setState(() => _output.text = directory);
  }

  Future<void> _refreshMountedLocations() async {
    final roots = <Directory>[];
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      final user = Platform.environment['USER'] ??
          Platform.environment['USERNAME'] ??
          (home.isEmpty ? '' : Directory(home).uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (user.isNotEmpty) {
        roots.add(Directory('/run/media/$user'));
        roots.add(Directory('/media/$user'));
      }
    } else if (Platform.isMacOS) {
      roots.add(Directory('/Volumes'));
    } else if (Platform.isWindows) {
      for (var code = 67; code <= 90; code++) {
        roots.add(Directory('${String.fromCharCode(code)}:\\'));
      }
    }
    final found = <({String label, String path})>[];
    final seen = <String>{};
    for (final root in roots) {
      try {
        if (!await root.exists()) continue;
        if (Platform.isWindows && root.path.length <= 3) {
          final key = root.path.toUpperCase();
          if (seen.add(key)) {
            found.add((label: 'Drive $key', path: root.path));
          }
          continue;
        }
        await for (final entity in root.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final path = entity.path;
          if (seen.add(path)) {
            final segments = entity.uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
            final label = segments.isEmpty ? path : segments.last;
            found.add((label: label, path: path));
          }
        }
      } on FileSystemException {
        // Ignore inaccessible mount roots and continue discovering the others.
      }
    }
    found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _mountedLocations
        ..clear()
        ..addAll(found);
      if (_selectedMount == null || !found.any((item) => item.path == _selectedMount)) {
        _selectedMount = found.length == 1 ? found.first.path : null;
      }
      if (found.isEmpty) {
        _status = 'No mounted removable drives found. Use Browse or Choose output.';
      } else {
        _status = 'Found ${found.length} available storage location(s).';
      }
    });
  }

  void _useMountedOutput() {
    final selected = _selectedMount;
    if (selected != null && mounted) setState(() => _output.text = selected);
  }

  Future<void> _browseMountedInput() async {
    final selected = _selectedMount;
    if (selected == null) return;
    final location = await openFile(
      confirmButtonText: 'Select OTA / payload file',
      initialDirectory: selected,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'OTA and payload files', extensions: ['zip', 'bin']),
      ],
    );
    if (location != null && mounted) setState(() => _source.text = location.path);
  }

  Future<void> _openOutput() async {
    final path = _output.text.trim();
    if (path.isEmpty) return;
    try {
      await Directory(path).create(recursive: true);
      final command = Platform.isWindows ? 'explorer' : Platform.isMacOS ? 'open' : 'xdg-open';
      await Process.start(command, [path], mode: ProcessStartMode.detached);
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not open output directory: ' + error.toString());
    }
  }

  void _drop(DropDoneDetails detail) {
    if (detail.files.isNotEmpty) setState(() => _source.text = detail.files.first.path);
  }

  Future<void> _inspect() async {
    if (_source.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'payload.inspect',
        {'source_path': _source.text.trim()},
        timeout: const Duration(minutes: 3),
      );
      final parts = (result.data['partitions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _selected.clear();
        _status = 'Found ' + parts.length.toString() + ' partitions.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    if (_source.text.trim().isEmpty || _output.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final result = await trackOperation(
        ref,
        operation: 'Payload extraction',
        target: _source.text.trim(),
        action: () => ref.read(backendClientProvider).request('payload.extract', {
          'source_path': _source.text.trim(),
          'output_dir': _output.text.trim(),
          'partitions': _selected.toList(),
          'sha256': _sha,
        }, timeout: const Duration(hours: 1)),
        successSummary: (value) =>
            ((value.data['files'] as List<dynamic>? ?? const []).length).toString() + ' image file(s) created.',
      );
      final count = (result.data['files'] as List<dynamic>? ?? const []).length;
      if (mounted) setState(() => _status = 'Created ' + count.toString() + ' image files.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Firmware & Payload',
    subtitle: 'Inspect OTA ZIP and payload BIN contents, review partition metadata, and extract verified image artifacts without overwriting existing files.',
    child: DropTarget(
      onDragDone: _drop,
      child: ListView(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _TextField(controller: _source, label: 'OTA ZIP or payload BIN path')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseSource, child: const Text('Browse…')),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _TextField(controller: _output, label: 'Output directory')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseOutput, child: const Text('Choose…')),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: _openOutput, child: const Text('Open folder')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _selectedMount,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mounted removable drive',
              border: OutlineInputBorder(),
            ),
            hint: const Text('Select mounted storage'),
            items: _mountedLocations.map((item) => DropdownMenuItem<String>(
              value: item.path,
              child: Text(item.label + ' · ' + item.path, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (value) => setState(() => _selectedMount = value),
          )),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Refresh mounted drives',
            onPressed: _refreshMountedLocations,
            icon: const Icon(Icons.refresh),
          ),
          OutlinedButton(
            onPressed: _selectedMount == null ? null : _useMountedOutput,
            child: const Text('Use for output'),
          ),
          OutlinedButton(
            onPressed: _selectedMount == null ? null : _browseMountedInput,
            child: const Text('Browse drive'),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: _busy ? null : _inspect, child: const Text('Inspect payload')),
          FilledButton.icon(
            onPressed: _busy ? null : _extract,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Extract selected (or all if none selected)'),
          ),
          FilterChip(
            label: const Text('SHA-256 fingerprints'),
            selected: _sha,
            onSelected: (value) => setState(() => _sha = value),
          ),
        ]),
        const SizedBox(height: 12),
        Text(_status),
        if (_parts.isNotEmpty) ...[
          Row(children: [
            Text(
              _parts.length.toString() + ' partitions · ' +
              _selected.length.toString() + ' selected · ' +
              _parts.where((part) => _selected.contains(part['name']))
                .fold<int>(0, (sum, part) => sum + ((part['size_bytes'] as num?)?.toInt() ?? 0)).toString() + ' B selected',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selected.addAll(_parts.map((p) => p['name'] as String))),
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Select none'),
            ),
          ]),
          _TextField(
            controller: _partitionFilter,
            label: 'Filter partitions',
            hint: 'Search by partition name',
            onChanged: (_) => setState(() {}),
          ),
          for (final part in _parts.where((part) =>
            (part['name'] as String).toLowerCase().contains(_partitionFilter.text.trim().toLowerCase())))
            CheckboxListTile(
              dense: true,
              value: _selected.contains(part['name']),
              title: Text(part['name'] as String),
              subtitle: Text(part['size_bytes'].toString() + ' bytes'),
              onChanged: (value) => setState(() {
                final name = part['name'] as String;
                if (value == true) {
                  _selected.add(name);
                } else {
                  _selected.remove(name);
                }
              }),
            ),
        ],
        const SizedBox(height: 12),
        Text('ACTIVITY LOG', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        _OutputPanel(output: _activityLines.isEmpty ? _status : _activityLines.join('\n')),
        if (_busy) ...[
          LinearProgressIndicator(value: _progress),
          if (_progress != null)
            Text('Extraction progress: ${(_progress! * 100).round()}%'),
        ],
      ]),
    ),
  );
}

String _redactDiagnosticText(String value) {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  var redacted = value;
  if (home != null && home.isNotEmpty) redacted = redacted.replaceAll(home, '<HOME>');
  redacted = redacted.replaceAllMapped(
    RegExp(r'(serial|device|target)(\s*[:=]\s*)([A-Za-z0-9._:-]{6,})', caseSensitive: false),
    (match) => '${match.group(1)}${match.group(2)}<DEVICE_ID>',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(r'(authorization\s*[:=]\s*bearer\s+|token|password|passwd|api[_-]?key)(\s*[:=]\s*)([^\s,;]+)', caseSensitive: false),
    (match) => '${match.group(1)}${match.group(2)}<REDACTED>',
  );
  return redacted;
}

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  Future<void> _openLogDirectory(BuildContext context) async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final directory = Directory(
      '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs',
    );
    try {
      await directory.create(recursive: true);
      final executable = Platform.isWindows
          ? 'explorer'
          : Platform.isMacOS
              ? 'open'
              : 'xdg-open';
      await Process.start(
        executable,
        [directory.path],
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open log folder: $error')),
        );
      }
    }
  }


  Future<void> _saveLogs(BuildContext context, WidgetRef ref) async {
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logs.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'DroidLab log files', extensions: ['log', 'txt']),
      ],
    );
    if (location == null) return;
    try {
      final diagnostics = ref.read(backendClientProvider).diagnostics;
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ?? Directory.current.path;
      final operationLog = File(
        '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs${Platform.pathSeparator}operations.log',
      );
      final contents = StringBuffer()
        ..writeln('DroidLab application logs')
        ..writeln('Exported: ${DateTime.now().toIso8601String()}')
        ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln()
        ..writeln('===== OPERATION CONSOLE =====');
      if (await operationLog.exists()) {
        contents.write(_redactDiagnosticText(await operationLog.readAsString()));
      } else {
        contents.writeln('No persisted operation-console log is available yet.');
      }
      contents
        ..writeln()
        ..writeln('===== BACKEND DIAGNOSTICS =====');
      if (diagnostics.isEmpty) {
        contents.writeln('No backend stderr diagnostics have been captured.');
      } else {
        contents.write(_redactDiagnosticText(diagnostics.join('\n')));
        contents.writeln();
      }
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(contents.toString(), flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logs saved to ${file.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save logs: $error')),
        );
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final location = await getSaveLocation(
      suggestedName: 'DroidLab-diagnostics.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Diagnostic text report', extensions: ['txt', 'log']),
      ],
    );
    if (location == null) return;
    try {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ?? Directory.current.path;
      final logDirectory = Directory(
        '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs',
      );
      final logFile = File(
        '${logDirectory.path}${Platform.pathSeparator}droidlab.log',
      );
      final diagnostics = ref.read(backendClientProvider).diagnostics;
      final pythonExecutable = Platform.environment['DROIDLAB_PYTHON'] ??
          (Platform.isWindows ? 'python' : 'python3');
      String pythonVersion = 'Unavailable';
      try {
        final version = await Process.run(pythonExecutable, ['--version']);
        pythonVersion = (version.stdout.toString() + version.stderr.toString()).trim();
      } catch (_) {
        // Preserve the report if Python cannot be queried independently.
      }
      final report = StringBuffer()
        ..writeln('DroidLab diagnostic report')
        ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('Python: $pythonVersion')
        ..writeln('Executable: ${Platform.resolvedExecutable}')
        ..writeln('Frozen build: true')
        ..writeln('Log directory: ${logDirectory.path}')
        ..writeln()
        ..writeln('--- Operation console (latest file) ---');
      final operationLog = File(
        '${logDirectory.path}${Platform.pathSeparator}operations.log',
      );
      if (await operationLog.exists()) {
        report.write(_redactDiagnosticText(await operationLog.readAsString()));
      } else {
        report.writeln('No persisted operation-console log found.');
      }
      report.writeln();
      report.writeln('--- Backend application log (latest file) ---');
      if (await logFile.exists()) {
        report.write(_redactDiagnosticText(await logFile.readAsString()));
      } else {
        report.writeln('No application log file found.');
        report.writeln();
        report.writeln('--- Backend diagnostics ---');
        if (diagnostics.isEmpty) {
          report.writeln('No backend stderr diagnostics captured.');
        } else {
          report.write(_redactDiagnosticText(diagnostics.join('\n')));
        }
      }
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(report.toString(), flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostic report saved to ${file.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export diagnostic report: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final diagnostics = ref.read(backendClientProvider).diagnostics;
    return _PageFrame(
      title: 'Logs & Diagnostics',
      subtitle: 'Diagnostics stay on this computer. Reports can contain device serials and command details; review before sharing.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _openLogDirectory(context),
          icon: const Icon(Icons.folder_open),
          label: const Text('Open logs folder'),
        ),
        OutlinedButton.icon(
          onPressed: () => _saveLogs(context, ref),
          icon: const Icon(Icons.save_alt),
          label: const Text('Save logs'),
        ),
        OutlinedButton.icon(
          onPressed: () => _exportReport(context, ref),
          icon: const Icon(Icons.save_alt),
          label: const Text('Export diagnostic report'),
        ),
      ],
      child: backend.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPanel(
          message: error.toString(),
          retry: () => ref.invalidate(backendReadyProvider),
        ),
        data: (_) => diagnostics.isEmpty
            ? const _EmptyPanel(
                icon: Icons.receipt_long,
                title: 'No backend warnings',
                message: 'Backend stderr diagnostics will appear here when available.',
              )
            : ListView.builder(
                itemCount: diagnostics.length,
                itemBuilder: (context, index) => SelectableText(
                  diagnostics[index],
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
      ),
    );
  }
}


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}';
    return _PageFrame(
      title: 'About DroidLab',
      subtitle: 'Android engineering workstation',
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'DL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DroidLab', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          Text('Flutter desktop · Version 0.1.0'),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text(
                    'A toolkit for Android device engineering and firmware workflows.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Discover and manage ADB and Fastboot devices, run guarded device operations, inspect and extract OTA payloads, capture logcat output, and review diagnostics.',
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.computer),
                    title: const Text('Platform'),
                    subtitle: Text(platform),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.code),
                    title: Text('Application'),
                    subtitle: Text('DroidLab Flutter Desktop'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.shield_outlined),
                    title: Text('Local-first'),
                    subtitle: Text('Device operations and diagnostic files are handled on this computer.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _python = TextEditingController();
  final _backend = TextEditingController();
  final _adb = TextEditingController();
  final _fastboot = TextEditingController();
  final _payloadDumper = TextEditingController();
  String _theme = 'cyberpunk_glass';
  bool _loaded = false;
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    ref.read(droidLabSettingsProvider.future).then((settings) {
      if (!mounted) return;
      _python.text = settings.pythonPath;
      _backend.text = settings.backendPath;
      _adb.text = settings.adbPath;
      _fastboot.text = settings.fastbootPath;
      _payloadDumper.text = settings.payloadDumperPath;
      setState(() {
        _theme = settings.theme;
        _loaded = true;
      });
    }).catchError((Object error) {
      if (mounted) setState(() {
        _loaded = true;
        _status = 'Could not load settings: $error';
      });
    });
  }

  @override
  void dispose() {
    _python.dispose();
    _backend.dispose();
    _adb.dispose();
    _fastboot.dispose();
    _payloadDumper.dispose();
    super.dispose();
  }

  Future<void> _browse(TextEditingController controller, String label) async {
    final file = await openFile();
    if (file != null && mounted) setState(() => controller.text = file.path);
  }

  Future<void> _save() async {
    if (_saving || !_loaded) return;
    setState(() {
      _saving = true;
      _status = '';
    });
    try {
      final settings = DroidLabSettings(
        theme: _theme,
        pythonPath: _python.text.trim(),
        backendPath: _backend.text.trim(),
        adbPath: _adb.text.trim(),
        fastbootPath: _fastboot.text.trim(),
        payloadDumperPath: _payloadDumper.text.trim(),
      );
      await ref.read(droidLabSettingsProvider.notifier).saveSettings(settings);
      if (mounted) setState(() => _status =
          'Settings saved. Python/backend changes take effect after restarting DroidLab; device-tool paths are read by the backend on the next command.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not save settings: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _toolField(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
        )),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Browse for $label',
          onPressed: () => _browse(controller, label),
          icon: const Icon(Icons.folder_open),
        ),
        IconButton(
          tooltip: 'Clear override and use automatic discovery',
          onPressed: () => setState(controller.clear),
          icon: const Icon(Icons.clear),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Settings',
      subtitle: 'Appearance and executable paths. Blank tool paths use bundled tools first, then system PATH.',
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('APPEARANCE', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _theme,
                    decoration: const InputDecoration(labelText: 'Color theme'),
                    items: const [
                      DropdownMenuItem(value: 'cyberpunk_glass', child: Text('Charcoal Blue (legacy default)')),
                      DropdownMenuItem(value: 'standard_dark', child: Text('Charcoal')),
                      DropdownMenuItem(value: 'oled_black', child: Text('OLED Black')),
                    ],
                    onChanged: (value) => setState(() => _theme = value ?? _theme),
                  ),
                ]),
              )),
              const SizedBox(height: 14),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TOOL LOCATIONS', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _toolField('Python executable', _python, 'python3 or full executable path'),
                  _toolField('Backend script', _backend, 'server.py'),
                  _toolField('ADB executable', _adb, 'adb'),
                  _toolField('Fastboot executable', _fastboot, 'fastboot'),
                  _toolField('Payload dumper', _payloadDumper, 'payload-dumper-go'),
                  Text(
                    'Settings are stored at ~/DroidLab/config.json, compatible with the legacy application.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              )),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Save settings'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_status, style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ]),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        )),
        ...actions,
      ]),
      const SizedBox(height: 20),
      Expanded(child: child),
    ],
  );
}

class _TextField extends StatelessWidget {
  const _TextField({required this.controller, required this.label, this.hint, this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.output});
  final String output;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: SelectableText(
      output,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 42),
      const SizedBox(height: 10),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      Text(message),
    ]),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 40),
      Text(message),
      const SizedBox(height: 8),
      FilledButton(onPressed: retry, child: const Text('Retry')),
    ]),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon),
          Text(title),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );
}
