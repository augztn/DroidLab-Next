part of 'feature_pages.dart';
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override ConsumerState<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends ConsumerState<DashboardPage> {
  Timer? _timer;
  bool _polling = false;
  String? _serial, _batteryError, _resourceError;
  int? _level;
  double? _temperature;
  List<String> _top = const [];
  DateTime? _updated;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _poll()); _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll()); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final data = await ref.read(deviceListProvider.future);
      final devices = (data['devices'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
      final selected = ref.read(selectedTargetSerialProvider);
      final adb = devices.where((d) => d['transport'] == 'adb' && d['state'] == 'device');
      final target = adb.where((d) => d['serial'] == selected).firstOrNull ?? adb.firstOrNull;
      if (target == null) { if (mounted) setState(() { _serial = null; _batteryError = 'Connect an authorized ADB device to view metrics.'; _top = const []; _resourceError = null; }); return; }
      final serial = target['serial']?.toString();
      if (serial == null || serial.isEmpty) return;
      final client = ref.read(backendClientProvider);
      // Run device shell reads sequentially. The backend serializes ADB shell
      // operations per device, so dispatching both at once can reject one request
      // or race a backend restart on slower desktop hosts.
      final batteryResult = await client.request(
        'adb.shell',
        {
          'serial': serial,
          'command_text': 'dumpsys battery',
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.shell',
            'serial': serial,
            'command_text': 'dumpsys battery',
          },
        },
        timeout: const Duration(seconds: 20),
      );
      final batteryText = batteryResult.data['output']?.toString() ?? '';
      final processesResult = await client.request(
        'adb.shell',
        {
          'serial': serial,
          'command_text': 'top -n 1 -m 5',
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.shell',
            'serial': serial,
            'command_text': 'top -n 1 -m 5',
          },
        },
        timeout: const Duration(seconds: 20),
      );
      final topText = processesResult.data['output']?.toString() ?? '';
      final lm = RegExp(r'^\s*level:\s*(\d+)', multiLine: true).firstMatch(batteryText);
      final tm = RegExp(r'^\s*temperature:\s*(-?\d+)', multiLine: true).firstMatch(batteryText);
      final level = lm == null ? null : int.tryParse(lm.group(1)!);
      final temp = tm == null ? null : double.tryParse(tm.group(1)!);
      final lines = topText.split(RegExp(r'\r?\n')).map((v) => v.trimRight()).where((v) => v.trim().isNotEmpty).toList();
      final processLines = lines.where((line) => RegExp(r'^\s*\d+\s+').hasMatch(line)).take(5).toList();
      final displayLines = processLines.isNotEmpty ? processLines : lines.take(14).toList();
      if (mounted) setState(() { _serial = serial; _level = level?.clamp(0, 100); _temperature = temp == null ? null : temp / 10; _batteryError = level == null ? 'Battery data was not present in the device response.' : null; _top = displayLines; _resourceError = displayLines.isEmpty ? 'No process data returned by Android.' : null; _updated = DateTime.now(); });
    } catch (error) {
      final message = error.toString();
      // A closed backend stdin means the managed Python process exited while
      // the client still held its Process handle. Recreate the client on the
      // next poll instead of leaving both dashboard widgets permanently stale.
      if (message.contains('Could not write to backend stdin') ||
          message.contains('Backend process exited unexpectedly')) {
        ref.invalidate(backendClientProvider);
        ref.invalidate(backendReadyProvider);
        ref.invalidate(deviceListProvider);
      }
      if (mounted) setState(() {
        _batteryError = 'Could not query device metrics: $message';
        _resourceError = 'Resource monitor unavailable: $message';
      });
    } finally { _polling = false; }
  }
  @override Widget build(BuildContext context) {
    final backend = ref.watch(backendReadyProvider);
    final devices = ref.watch(discoveredDevicesProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1500;
    final colors = Theme.of(context).colorScheme;
    return _PageFrame(title: 'Dashboard', subtitle: 'Android engineering workstation overview.',
      actions: [OutlinedButton.icon(onPressed: _polling ? null : _poll, icon: const Icon(Icons.refresh, size: 17), label: const Text('Refresh device metrics'))],
      child: ListView(children: [
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: wide ? 3 : 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.2, children: [
          _MetricCard(title: 'Backend', icon: Icons.hub, value: backend.when(data: (_) => 'Online', error: (_, __) => 'Unavailable', loading: () => 'Starting')),
          _MetricCard(title: 'Connected devices', icon: Icons.devices, value: devices.when(data: (v) => v.length.toString(), error: (_, __) => '—', loading: () => '…')),
          const _MetricCard(title: 'Desktop', value: 'Ready', icon: Icons.desktop_windows),
        ]),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.battery_charging_full, color: colors.primary), const SizedBox(width: 10), Expanded(child: Text('Device Battery Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), if (_serial != null) Text(_serial!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, fontFamily: 'monospace'))]),
          const SizedBox(height: 16),
          if (_batteryError != null) Text(_batteryError!, style: TextStyle(color: colors.onSurfaceVariant))
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_level == null ? '—' : _level.toString() + '%', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)), const Spacer(), Text(_temperature == null ? 'Temperature —' : 'Temperature ' + _temperature!.toStringAsFixed(1) + ' °C', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant))]),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _level == null ? null : _level! / 100, minHeight: 12, backgroundColor: colors.surfaceContainerHighest)),
            const SizedBox(height: 8),
            Text('Source: adb shell dumpsys battery · Auto-refresh every 5 seconds', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ]))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.monitor_heart_outlined, color: colors.primary), const SizedBox(width: 10), Expanded(child: Text('System Resource Monitor', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), Text(_updated == null ? 'Waiting for sample' : 'Updated ' + _updated!.toLocal().toIso8601String().substring(11, 19), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))]),
          const SizedBox(height: 6),
          Text('Top CPU-intensive processes · adb shell top -n 1 -m 5 · Auto-refresh every 5 seconds', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_resourceError != null) Text(_resourceError!, style: TextStyle(color: colors.onSurfaceVariant))
          else Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(9), border: Border.all(color: colors.outlineVariant)), child: SelectableText(_top.join('\n'), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.5))),
        ]))),
      ]),
    );
  }
}
