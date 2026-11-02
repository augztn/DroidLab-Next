part of 'feature_pages.dart';

class DebloaterPage extends ConsumerStatefulWidget {
  const DebloaterPage({super.key});
  @override
  ConsumerState<DebloaterPage> createState() => _DebloaterPageState();
}

class _DebloaterPageState extends ConsumerState<DebloaterPage> {
  String? _serial;
  int _userId = 0;
  String _query = '';
  String _filter = 'all';
  bool _busy = false;
  List<Map<String, dynamic>> _packages = const [];
  Set<String> _disabled = {};
  int _loadGeneration = 0;
  String? _error;

  Future<void> _load() async {
    final serial = _serial;
    if (serial == null || _busy) return;
    final generation = ++_loadGeneration;
    setState(() { _busy = true; _error = null; });
    try {
      final client = ref.read(backendClientProvider);
      final inventory = await client.request('debloat.packages.list', {'serial': serial, 'user_id': _userId});
      final packages = (inventory.data['packages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList(growable: false);
      final disabled = packages
          .where((item) => item['disabled'] == true)
          .map((item) => item['package'] as String)
          .toSet();
      if (!mounted || generation != _loadGeneration || serial != _serial) return;
      setState(() { _packages = packages; _disabled = disabled; });
    } catch (error) {
      if (mounted && generation == _loadGeneration) setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> item, String action) async {
    final serial = _serial;
    if (serial == null) return;
    final package = item['package'] as String;
    final label = action == 'disable' ? 'Disable' : 'Uninstall for user';
    final explanation = action == 'uninstall'
        ? 'This uninstalls the package for Android user ' + _userId.toString() + '. It does not remove the APK from a read-only system partition. Some dependent features may stop working.'
        : 'This disables the package for Android user ' + _userId.toString() + '. Dependent system features may stop working.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label + ' package?'),
        content: SelectableText(package + '\n\nTarget: ' + serial + ' · user ' + _userId.toString() + '\n\n' + explanation + '\n\nReview package purpose and keep a recovery plan before continuing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(label)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await trackOperation(ref, operation: 'Android package ' + action, target: serial, action: () async {
        final intent = {
          'operation': 'debloat.package.apply',
          'serial': serial,
          'package': package,
          'action': action,
          'user_id': _userId,
        };
        return ref.read(backendClientProvider).request('debloat.package.apply', {
          ...intent, 'confirmed': true, 'confirmation': intent,
        });
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceResult = ref.watch(deviceListProvider);
    final adbDevices = (deviceResult.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((item) => item['transport'] == 'adb' && item['state'] == 'device')
        .toList(growable: false);
    final serials = adbDevices.map((item) => item['serial'] as String).toList();
    if (_serial != null && !serials.contains(_serial)) {
      _serial = null;
      _packages = const [];
      _disabled = {};
    }
    final visible = _packages.where((item) {
      final package = item['package'] as String;
      final system = item['system'] == true;
      if (_filter == 'system' && !system) return false;
      if (_filter == 'user' && system) return false;
      final query = _query.trim().toLowerCase();
      return query.isEmpty || package.toLowerCase().contains(query);
    }).toList(growable: false);

    return _PageFrame(
      title: 'Android Debloater',
      subtitle: 'Inspect installed packages. Every package change requires explicit confirmation.',
      actions: [
        IconButton(onPressed: _busy || _serial == null ? null : _load, tooltip: 'Refresh packages', icon: const Icon(Icons.refresh)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(
          spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 280, child: DropdownButtonFormField<String>(
              value: _serial,
              decoration: const InputDecoration(labelText: 'Authorized ADB device', border: OutlineInputBorder()),
              items: serials.map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _busy ? null : (value) => setState(() { _loadGeneration++; _serial = value; _packages = const []; _disabled = {}; }),
            )),
            SizedBox(width: 130, child: TextFormField(
              initialValue: '0', keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Android user ID', border: OutlineInputBorder()),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 0 && parsed <= 2147483647 && !_busy) {
                  setState(() { _loadGeneration++; _userId = parsed; _packages = const []; _disabled = {}; });
                }
              },
            )),
            FilledButton.icon(onPressed: _serial == null || _busy ? null : _load, icon: const Icon(Icons.list), label: const Text('Load packages')),
          ],
        ))),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded), SizedBox(width: 8),
            Expanded(child: Text('System-app changes can break Android features. Uninstall for user does not remove the system image APK. Package guidance is device-dependent; no package is automatically marked safe.')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search package IDs', border: OutlineInputBorder()),
              onChanged: (value) => setState(() => _query = value),
            )),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'user', child: Text('User apps')),
                DropdownMenuItem(value: 'system', child: Text('System apps')),
              ],
              onChanged: (value) => setState(() => _filter = value ?? 'all'),
            ),
          ]),
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 8),
        Expanded(child: _busy
          ? const Center(child: CircularProgressIndicator())
          : _serial == null
              ? const _EmptyPanel(icon: Icons.usb_off, title: 'Select an authorized device', message: 'Connect a phone, enable USB debugging, authorize it, then refresh devices.')
              : _packages.isEmpty
                  ? const _EmptyPanel(icon: Icons.apps, title: 'No package inventory loaded', message: 'Load packages to inspect the selected Android user.')
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final package = item['package'] as String;
                        final system = item['system'] == true;
                        final disabled = _disabled.contains(package);
                        return Card(child: ListTile(
                          leading: Icon(system ? Icons.android : Icons.apps),
                          title: SelectableText(package),
                          subtitle: Text((system ? 'System package' : 'User package') + ' · ' + (disabled ? 'Disabled' : 'Enabled')),
                          trailing: Wrap(spacing: 4, children: [
                            TextButton(onPressed: _busy || disabled ? null : () => _apply(item, 'disable'), child: const Text('Disable')),
                            TextButton(onPressed: _busy ? null : () => _apply(item, 'uninstall'), child: const Text('Uninstall')),
                          ]),
                        ));
                      },
                    )),
        Align(alignment: Alignment.centerLeft, child: Text(visible.length.toString() + ' of ' + _packages.length.toString() + ' packages · ' + _disabled.length.toString() + ' disabled', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
