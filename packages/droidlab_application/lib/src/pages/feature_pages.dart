import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/backend_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final devices = ref.watch(deviceListProvider);
    return _PageFrame(
      title: 'Dashboard',
      subtitle: 'Android engineering workstation overview.',
      child: GridView.count(
        crossAxisCount: MediaQuery.sizeOf(context).width > 1500 ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: [
          _MetricCard(title: 'Backend', icon: Icons.hub,
            value: backend.when(data: (_) => 'Online', error: (_, __) => 'Unavailable', loading: () => 'Starting')),
          _MetricCard(title: 'Connected devices', icon: Icons.devices,
            value: devices.when(data: (d) => '${(d['devices'] as List).length}', error: (_, __) => '—', loading: () => '…')),
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
      actions: [IconButton(onPressed: () => ref.invalidate(deviceListProvider), tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
      child: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorPanel(message: e.toString(), retry: () => ref.invalidate(deviceListProvider)),
        data: (data) {
          final list = (data['devices'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final warnings = data['warnings'] as List<dynamic>? ?? const [];
          if (list.isEmpty) return const _EmptyPanel(icon: Icons.usb_off, title: 'No devices detected', message: 'Connect a device in ADB or Fastboot mode, then refresh.');
          return ListView(children: [
            for (final item in list)
              Card(child: ListTile(
                leading: Icon(item['transport'] == 'fastboot' ? Icons.memory : Icons.phone_android),
                title: Text(item['serial'] as String),
                subtitle: Text('${item['transport']} · ${item['state']}'),
                trailing: const Icon(Icons.circle, size: 9, color: Colors.green),
              )),
            for (final warning in warnings)
              ListTile(leading: const Icon(Icons.warning_amber), title: Text('${warning['transport']} scan warning'), subtitle: Text('${warning['message']}')),
          ]);
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
  String _output = '';
  bool _busy = false;
  @override
  void dispose() { _serial.dispose(); _command.dispose(); super.dispose(); }

  Future<void> _run() async {
    if (_serial.text.trim().isEmpty || _command.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request('adb.shell', {
        'serial': _serial.text.trim(), 'command': [_command.text.trim()],
      });
      setState(() => _output = result.data['output'] as String? ?? 'Command completed.');
    } catch (error) { setState(() => _output = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _reboot(String mode) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm device reboot'),
      content: Text('Send a reboot request to $serial into $mode mode?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
      ],
    ));
    if (confirmed != true) return;
    try {
      final result = await ref.read(backendClientProvider).request('adb.reboot', {'serial': serial, 'mode': mode, 'confirmed': true});
      setState(() => _output = result.data.toString());
    } catch (error) { setState(() => _output = error.toString()); }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'ADB Toolkit',
    subtitle: 'Device-targeted shell diagnostics and guarded reboot workflows.',
    child: ListView(children: [
      _TextField(controller: _serial, label: 'Device serial'),
      const SizedBox(height: 12),
      _TextField(controller: _command, label: 'Android shell command'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : _run, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow), label: const Text('Run command')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('system'), child: const Text('Reboot')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('bootloader'), child: const Text('Bootloader')),
        OutlinedButton(onPressed: _busy ? null : () => _reboot('recovery'), child: const Text('Recovery')),
      ]),
      const SizedBox(height: 18),
      _OutputPanel(output: _output.isEmpty ? 'Command output appears here.' : _output),
    ]),
  );
}

class FastbootToolkitPage extends ConsumerStatefulWidget {
  const FastbootToolkitPage({super.key});
  @override
  ConsumerState<FastbootToolkitPage> createState() => _FastbootToolkitPageState();
}
class _FastbootToolkitPageState extends ConsumerState<FastbootToolkitPage> {
  final _serial = TextEditingController(), _partition = TextEditingController(), _image = TextEditingController();
  String _output = '';
  bool _busy = false;
  @override
  void dispose() { _serial.dispose(); _partition.dispose(); _image.dispose(); super.dispose(); }

  Future<void> _mutate(String operation) async {
    final serial = _serial.text.trim(), partition = _partition.text.trim(), image = _image.text.trim();
    if (serial.isEmpty || partition.isEmpty || (operation == 'fastboot.flash' && image.isEmpty)) return;
    final command = operation == 'fastboot.flash'
        ? 'fastboot -s $serial flash $partition $image'
        : 'fastboot -s $serial erase $partition';
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(operation == 'fastboot.flash' ? 'Confirm partition flash' : 'Confirm partition erase'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Target: $serial'), Text('Partition: $partition'),
        if (operation == 'fastboot.flash') Text('Image: $image'),
        const SizedBox(height: 12),
        const Text('This operation modifies device partitions and may make the device unbootable.'),
        const SizedBox(height: 12),
        SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I understand — execute')),
      ],
    ));
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final args = <String, dynamic>{'serial': serial, 'partition': partition, 'confirmed': true};
      if (operation == 'fastboot.flash') args['image_path'] = image;
      final result = await ref.read(backendClientProvider).request(operation, args, timeout: const Duration(minutes: 20));
      setState(() => _output = result.data.toString());
    } catch (error) { setState(() => _output = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
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
      _TextField(controller: _image, label: 'Image path', hint: '/path/to/boot.img'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : () => _mutate('fastboot.flash'), icon: const Icon(Icons.flash_on), label: const Text('Flash image')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _mutate('fastboot.erase'), icon: const Icon(Icons.delete_outline), label: const Text('Erase partition')),
      ]),
      const SizedBox(height: 18),
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
  final _source = TextEditingController(), _output = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _parts = [];
  String _status = 'Drop an OTA ZIP or payload BIN file here, or enter its path.';
  bool _busy = false, _sha = false;
  @override
  void dispose() { _source.dispose(); _output.dispose(); super.dispose(); }
  void _drop(DropDoneDetails detail) { if (detail.files.isNotEmpty) setState(() => _source.text = detail.files.first.path); }

  Future<void> _inspect() async {
    if (_source.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request('payload.inspect', {'source_path': _source.text.trim()}, timeout: const Duration(minutes: 3));
      final parts = (result.data['partitions'] as List<dynamic>).cast<Map<String, dynamic>>();
      setState(() { _parts = parts; _selected.clear(); _status = 'Found ${parts.length} partitions.'; });
    } catch (error) { setState(() => _status = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _extract() async {
    if (_source.text.trim().isEmpty || _output.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request('payload.extract', {
        'source_path': _source.text.trim(), 'output_dir': _output.text.trim(),
        'partitions': _selected.toList(), 'sha256': _sha,
      }, timeout: const Duration(hours: 1));
      final count = (result.data['files'] as List<dynamic>? ?? const []).length;
      setState(() => _status = 'Created $count image files.');
    } catch (error) { setState(() => _status = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Payload Extractor',
    subtitle: 'Inspect OTA metadata and extract verified images without overwriting existing files.',
    child: DropTarget(onDragDone: _drop, child: ListView(children: [
      _TextField(controller: _source, label: 'OTA ZIP or payload BIN path'),
      const SizedBox(height: 10),
      _TextField(controller: _output, label: 'Output directory'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy ? null : _inspect, child: const Text('Inspect payload')),
        FilledButton.icon(onPressed: _busy ? null : _extract, icon: const Icon(Icons.archive_outlined), label: const Text('Extract selected')),
        FilterChip(label: const Text('SHA-256 fingerprints'), selected: _sha, onSelected: (value) => setState(() => _sha = value)),
      ]),
      const SizedBox(height: 12),
      Text(_status),
      if (_parts.isNotEmpty) ...[
        Row(children: [
          Text('${_parts.length} partitions', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: () => setState(() => _selected.addAll(_parts.map((p) => p['name'] as String))), child: const Text('Select all')),
          TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Clear')),
        ]),
        for (final part in _parts)
          CheckboxListTile(dense: true, value: _selected.contains(part['name']),
            title: Text(part['name'] as String), subtitle: Text('${part['size_bytes']} bytes'),
            onChanged: (value) => setState(() => value == true ? _selected.add(part['name'] as String) : _selected.remove(part['name'] as String))),
      ],
      if (_busy) const LinearProgressIndicator(),
    ])),
  );
}

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _PageFrame(
    title: 'Logs & Diagnostics',
    subtitle: 'Backend process diagnostics and runtime health.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Backend diagnostics are emitted on stderr and retained in a bounded buffer.'),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => ref.invalidate(backendReadyProvider), child: const Text('Reconnect backend')),
      const SizedBox(height: 12),
      Expanded(child: Consumer(builder: (context, ref, _) {
        final client = ref.watch(backendClientProvider);
        return ListView(children: [for (final line in client.diagnostics) SelectableText(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))]);
      })),
    ]),
  );
}
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const _PageFrame(
    title: 'Settings', subtitle: 'Runtime configuration and tool discovery.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(title: Text('ADB'), subtitle: Text('DROIDLAB_ADB_PATH or adb on PATH')),
      ListTile(title: Text('Fastboot'), subtitle: Text('DROIDLAB_FASTBOOT_PATH or fastboot on PATH')),
      ListTile(title: Text('Python'), subtitle: Text('DROIDLAB_PYTHON or python3/python on PATH')),
      ListTile(title: Text('Payload dumper'), subtitle: Text('payload-dumper-go on PATH or bundled with the application')),
    ]),
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.title, required this.subtitle, required this.child, this.actions = const [], super.key});
  final String title, subtitle; final Widget child; final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6), Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
    ])), ...actions]),
    const SizedBox(height: 20), Expanded(child: child),
  ]);
}
class _TextField extends StatelessWidget {
  const _TextField({required this.controller, required this.label, this.hint});
  final TextEditingController controller; final String label; final String? hint;
  @override
  Widget build(BuildContext context) => TextField(controller: controller, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()));
}
class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.output}); final String output;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
    child: SelectableText(output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)));
}
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  final IconData icon; final String title, message;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 42), const SizedBox(height: 10), Text(title, style: Theme.of(context).textTheme.titleLarge), Text(message),
  ]));
}
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.retry});
  final String message; final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 40), Text(message), const SizedBox(height: 8), FilledButton(onPressed: retry, child: const Text('Retry')),
  ]));
}
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});
  final String title, value; final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [Icon(icon), Text(title), Text(value, style: Theme.of(context).textTheme.headlineSmall)],
  )));
}
