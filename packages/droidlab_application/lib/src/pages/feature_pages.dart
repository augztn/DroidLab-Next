import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter/material.dart';
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
                    onPressed: () => Clipboard.setData(ClipboardData(text: serial)),
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
  final List<String> _logLines = [];
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
    unawaited(_eventSubscription?.cancel() ?? Future<void>.value());
    _serial.dispose();
    _command.dispose();
    _package.dispose();
    _bugreport.dispose();
    _logcatFilters.dispose();
    _logSavePath.dispose();
    super.dispose();
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
  Widget build(BuildContext context) => _PageFrame(
    title: 'ADB Toolkit',
    subtitle: 'Diagnostics and device operations require an explicit serial target.',
    child: ListView(children: [
      _TextField(controller: _serial, label: 'ADB serial'),
      const SizedBox(height: 12),
      _TextField(controller: _command, label: 'Android shell command'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy ? null : _runShell, child: const Text('Run shell command')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('system'), child: const Text('Reboot')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('bootloader'), child: const Text('Bootloader')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('recovery'), child: const Text('Recovery')),
        OutlinedButton(onPressed: _busy ? null : _loadDeviceInfo, child: const Text('Device info')),
        OutlinedButton(
          onPressed: _logcatRequestId == null ? _startLogcat : _stopLogcat,
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
      OutlinedButton(onPressed: _busy ? null : _sideload, child: const Text('Sideload OTA')),
      const SizedBox(height: 12),
      _TextField(controller: _bugreport, label: 'Bugreport output ZIP path'),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _busy ? null : _createBugreport, child: const Text('Generate bugreport')),
      const SizedBox(height: 18),
      if (_busy) const LinearProgressIndicator(),
      _OutputPanel(output: _output.isEmpty ? 'Command output appears here.' : _output),
      if (_logLines.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('LIVE LOGCAT', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        _OutputPanel(output: _logLines.join('\n')),
      ],
    ]),
  );
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
  String _output = '';
  bool _busy = false;

  @override
  void dispose() {
    _serial.dispose();
    _partition.dispose();
    _image.dispose();
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

  Future<void> _rebootFastboot() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Fastboot reboot'),
        content: Text('Reboot Fastboot target ' + serial + ' to Android?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await trackOperation(
        ref,
        operation: 'Fastboot reboot',
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          'fastboot.reboot',
          {
            'serial': serial,
            'confirmed': true,
            'confirmation': {'operation': 'fastboot.reboot', 'serial': serial},
          },
        ),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Fastboot Toolkit',
    subtitle: 'Destructive actions require fresh target validation and an explicit confirmation.',
    child: ListView(children: [
      _TextField(controller: _serial, label: 'Fastboot serial'),
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
          label: const Text('Erase partition'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _rebootFastboot,
          child: const Text('Reboot'),
        ),
      ]),
      const SizedBox(height: 18),
      if (_busy) const LinearProgressIndicator(),
      _OutputPanel(output: _output.isEmpty ? 'Fastboot operation results appear here.' : _output),
    ]),
  );
}

class PayloadExtractorPage extends ConsumerStatefulWidget {
  const PayloadExtractorPage({super.key});

  @override
  ConsumerState<PayloadExtractorPage> createState() => _PayloadExtractorPageState();
}

class _PayloadExtractorPageState extends ConsumerState<PayloadExtractorPage> {
  final _source = TextEditingController();
  final _output = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _parts = [];
  String _status = 'Drop an OTA ZIP or payload BIN file here, or enter its path.';
  bool _busy = false;
  bool _sha = false;

  @override
  void dispose() {
    _source.dispose();
    _output.dispose();
    super.dispose();
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
    title: 'Payload Extractor',
    subtitle: 'Inspect OTA metadata and extract verified images without overwriting existing files.',
    child: DropTarget(
      onDragDone: _drop,
      child: ListView(children: [
        _TextField(controller: _source, label: 'OTA ZIP or payload BIN path'),
        const SizedBox(height: 10),
        _TextField(controller: _output, label: 'Output directory'),
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
            Text(_parts.length.toString() + ' partitions', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selected.addAll(_parts.map((p) => p['name'] as String))),
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear'),
            ),
          ]),
          for (final part in _parts)
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const variables = [
      ('Python executable', 'DROIDLAB_PYTHON'),
      ('Backend script', 'DROIDLAB_BACKEND_SCRIPT'),
      ('ADB executable', 'DROIDLAB_ADB_PATH'),
      ('Fastboot executable', 'DROIDLAB_FASTBOOT_PATH'),
      ('Payload dumper', 'DROIDLAB_PAYLOAD_DUMPER_GO_PATH'),
    ];
    return _PageFrame(
      title: 'Settings',
      subtitle: 'Runtime tool configuration is currently read from the process environment.',
      child: ListView(children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Set these environment variables before launching DroidLab. Editable in-app preferences and migration from the legacy config file are not part of this build.',
            ),
          ),
        ),
        for (final item in variables)
          ListTile(
            title: Text(item.$1),
            subtitle: SelectableText(
              Platform.environment[item.$2]?.isNotEmpty == true
                  ? Platform.environment[item.$2]!
                  : 'Auto-discovery / default',
            ),
            trailing: Text(item.$2, style: Theme.of(context).textTheme.labelSmall),
          ),
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
  const _TextField({required this.controller, required this.label, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
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
