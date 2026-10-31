import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/backend_providers.dart';
import '../state/operation_history.dart';

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
                  trailing: IconButton(
                    tooltip: 'Copy serial',
                    icon: const Icon(Icons.copy),
                    onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: serial))),
                  ),
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
  List<String> _pausedLogSnapshot = [];
  bool _logPaused = false;
  StreamSubscription<BackendEvent>? _eventSubscription;
  String? _logcatRequestId;
  String _output = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventSubscription = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'logcat' && mounted) {
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
      if (mounted) setState(() => _output = 'Device scan completed. Select the intended ADB serial below.');
    } catch (error) {
      if (mounted) setState(() => _output = 'Device scan failed: $error');
    }
  }

  Future<void> _runShell() async {
    final serial = _serial.text.trim();
    final command = _command.text.trim();
    if (serial.isEmpty || command.isEmpty || _busy) return;
    final potentiallyDestructive = RegExp(
      r'(^|[;&|]\s*)(rm\s+-.*r|mkfs(\.[\w-]+)?|dd\s|reboot\b|poweroff\b|shutdown\b|setprop\b|pm\s+(uninstall|disable-user)\b|svc\b.*\bdisable\b|wipe\b|format\b)',
      caseSensitive: false,
    ).hasMatch(command);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(potentiallyDestructive
            ? 'Potentially destructive shell command'
            : 'Confirm ADB shell command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            const SizedBox(height: 8),
            SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            Text(potentiallyDestructive
                ? 'This command may modify system state or remove data. Review it carefully before execution.'
                : 'Review the exact device target and command. DroidLab requires confirmation before dispatching shell commands.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Execute command')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB shell',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.shell', {
          'serial': serial,
          'command': [command],
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.shell',
            'serial': serial,
            'command': [command],
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
    }
  }

  Future<void> _startLogcat() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _logcatRequestId != null) return;
    final filters = _logcatFilters.text.trim().isEmpty
        ? <String>[]
        : _logcatFilters.text.trim().split(RegExp(r'\s+'));
    try {
      final handle = await ref.read(backendClientProvider).startOperation(
        'adb.logcat.start',
        {'serial': serial, 'filters': filters},
      );
      if (!mounted) {
        await ref.read(backendClientProvider).cancel(handle.requestId);
        return;
      }
      setState(() {
        _logcatRequestId = handle.requestId;
        _logLines.clear();
        _pausedLogSnapshot = [];
        _logPaused = false;
      });
      unawaited(trackOperation(
        ref,
        operation: 'ADB logcat',
        target: serial,
        action: () => handle.result,
        successSummary: (_) => 'Logcat stream stopped.',
      ).then((result) {
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = result.data.toString();
          });
        }
      }, onError: (Object error) {
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = error.toString();
          });
        }
      }));
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    }
  }

  Future<void> _stopLogcat() async {
    final id = _logcatRequestId;
    if (id == null) return;
    await ref.read(backendClientProvider).cancel(id);
    if (mounted) setState(() => _logcatRequestId = null);
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
    if (serial.isEmpty) return;
    try {
      final result = await ref.read(backendClientProvider).request(
        'adb.device_info',
        {'serial': serial},
      );
      if (mounted) {
        final properties = result.data['properties'] as Map<String, dynamic>;
        setState(() {
          _output = properties.entries
              .map((entry) => entry.key + ': ' + entry.value.toString())
              .join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
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
    final selectedAdbState = selectedTransport == 'adb'
        ? selectedDevice?['state'] as String?
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
        Expanded(child: _TextField(controller: _serial, label: 'ADB serial')),
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
      const SizedBox(height: 12),
      _TextField(controller: _command, label: 'Android shell command'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy || !canRunAdbCommands ? null : _runShell, child: const Text('Run shell command')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('system'), child: const Text('Reboot')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('bootloader'), child: const Text('Bootloader')),
        OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('recovery'), child: const Text('Recovery')),
        OutlinedButton(onPressed: _busy || !canRunAdbCommands ? null : _loadDeviceInfo, child: const Text('Device info')),
        OutlinedButton(
          onPressed: _logcatRequestId != null ? _stopLogcat : (canRunAdbCommands ? _startLogcat : null),
          child: Text(_logcatRequestId == null ? 'Start logcat' : 'Stop logcat'),
        ),
      ]),
      const SizedBox(height: 14),
      _TextField(controller: _logcatFilters, label: 'Logcat filters (optional)', hint: '*:W or ActivityManager:I'),
      const SizedBox(height: 8),
      _TextField(controller: _logSavePath, label: 'Logcat save path'),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _saveLogcat, child: const Text('Save captured logcat')),
      const SizedBox(height: 8),
      DropTarget(
        onDragDone: (detail) {
          if (detail.files.isNotEmpty) setState(() => _package.text = detail.files.first.path);
        },
        child: _TextField(controller: _package, label: 'Recovery OTA ZIP path'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy || !(selectedAdbState == 'device' || selectedAdbState == 'recovery' || selectedAdbState == 'sideload') ? null : _sideload,
        child: const Text('Sideload OTA'),
      ),
      const SizedBox(height: 12),
      _TextField(controller: _bugreport, label: 'Bugreport output ZIP path'),
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

  @override
  void dispose() {
    _serial.dispose();
    _partition.dispose();
    _image.dispose();
    _advancedCommand.dispose();
    super.dispose();
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
    final label = mode == 'system' ? 'Android' : mode;
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
    }
  }

  Future<void> _runAdvancedCommand() async {
    final serial = _serial.text.trim();
    final command = _advancedCommand.text.trim();
    if (serial.isEmpty || command.isEmpty || _busy) return;
    final preview = 'fastboot -s ' + serial + ' ' + command;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm advanced Fastboot command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            const SizedBox(height: 8),
            const Text(
              'Advanced commands are unrestricted and may erase data, change boot state, or make the device unbootable. Review the exact command.',
            ),
            const SizedBox(height: 12),
            SelectableText(preview, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
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
        target: serial,
        action: () => ref.read(backendClientProvider).request('fastboot.command', {
          'serial': serial,
          'command': command,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.command',
            'serial': serial,
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
      _TextField(controller: _partition, label: 'Partition name', hint: 'boot_a'),
      const SizedBox(height: 12),
      DropTarget(
        onDragDone: _acceptImageDrop,
        child: _TextField(controller: _image, label: 'Image path', hint: 'Drop a partition .img or enter its path'),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
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
      Text('ADVANCED FASTBOOT COMMAND', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _TextField(
        controller: _advancedCommand,
        label: 'Fastboot arguments',
        hint: 'getvar all · flashing get_unlock_ability',
        onChanged: (value) => setState(() {
          _advancedPreview = value.trim().isEmpty
              ? ''
              : 'fastboot -s ' + _serial.text.trim() + ' ' + value.trim();
        }),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: () => setState(() {
            _advancedPreview = _advancedCommand.text.trim().isEmpty
                ? ''
                : 'fastboot -s ' + _serial.text.trim() + ' ' + _advancedCommand.text.trim();
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
  StreamSubscription<BackendEvent>? _events;
  List<Map<String, dynamic>> _parts = [];
  String _status = 'Drop an OTA ZIP or payload BIN file here, or enter its path.';
  bool _busy = false;
  bool _sha = false;

  @override
  void initState() {
    super.initState();
    _events = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'payload' && mounted) {
        setState(() {
          _activityLines.add(event.line);
          if (_activityLines.length > 300) {
            _activityLines.removeRange(0, _activityLines.length - 300);
          }
        });
      }
    });
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
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
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
        if (_busy) const LinearProgressIndicator(),
      ]),
    ),
  );
}

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final diagnostics = ref.read(backendClientProvider).diagnostics;
    return _PageFrame(
      title: 'Logs & Diagnostics',
      subtitle: 'Recent bounded backend diagnostics. Device output remains local and is not uploaded.',
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
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: [])],
    );
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
      await ref.read(droidLabSettingsProvider.notifier).update(settings);
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
