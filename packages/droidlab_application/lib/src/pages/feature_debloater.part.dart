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
  String _riskFilter = 'all';
  Map<String, Map<String, dynamic>> _guidance = const {};
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
      final catalogResult = await client.request('debloat.catalog.list', const {});
      final recommendationPackages = (catalogResult.data['recommendations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) => item['package'] is String)
          .map((item) => item['package'] as String)
          .toSet();
      final catalog = <String, Map<String, dynamic>>{};
      final inventory = await client.request('debloat.packages.list', {'serial': serial, 'user_id': _userId});
      final packages = (inventory.data['packages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList(growable: false);
      final disabled = packages
          .where((item) => item['disabled'] == true)
          .map((item) => item['package'] as String)
          .toSet();
      if (!mounted || generation != _loadGeneration || serial != _serial) return;
      setState(() {
        _packages = packages;
        _disabled = disabled;
        _guidance = {
          for (final package in packages)
            if (recommendationPackages.contains(package['package']))
              package['package'] as String: {
                'package': package['package'],
                'risk': 'Recommended — review first',
                'recommendation': 'Recommended — review first',
              },
        };
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _busy = false);
    }
  }


  Future<void> _showGuidance(Map<String, dynamic> item) async {
    final package = item['package'] as String;
    Map<String, dynamic> details;
    try {
      final response = await ref.read(backendClientProvider).request(
        'debloat.package.guidance',
        {'package': package},
      );
      details = response.data;
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    final system = item['system'] == true;
    final risk = (details['risk'] as String?) ?? 'Not listed — review manually';
    final explanation = (details['function'] as String?) ?? 'No verified package description is available for this exact ID.';
    final impact = (details['impact'] as String?) ?? 'No device-specific impact information is available.';
    final recommendation = (details['recommendation'] as String?) ?? 'Not listed';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text((details['app'] as String?)?.isNotEmpty == true ? details['app'] as String : package),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(package, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Text('Risk: $risk', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(explanation),
              const SizedBox(height: 12),
              Text('What happens if removed', style: Theme.of(context).textTheme.titleSmall),
              Text(impact),
              const SizedBox(height: 12),
              Text('Recommendation: $recommendation', style: Theme.of(context).textTheme.titleSmall),
              if (system) const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('This is a system package. Its dependencies and feature impact vary by device and OS build. Review carefully.'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Guidance is advisory, not proof that a package is safe to remove. Not listed does not mean safe or unsafe.'),
              ),
            ],
          )),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
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
      final guidance = _guidance[package];
      final risk = (guidance?['risk'] as String? ?? 'Not listed').toLowerCase();
      if (_riskFilter == 'recommended' && guidance == null) return false;
      if (_riskFilter == 'advanced' && !risk.contains('advanced')) return false;
      if (_riskFilter == 'review' && !(risk.contains('review') || risk.contains('unclear') || risk.contains('not listed'))) return false;
      if (_riskFilter == 'keep' && !(risk.contains('critical') || risk.startsWith('high') || risk.contains('keep'))) return false;
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              FilterChip(label: const Text('Recommended'), selected: _riskFilter == 'recommended', onSelected: (_) => setState(() => _riskFilter = _riskFilter == 'recommended' ? 'all' : 'recommended')),
              FilterChip(label: const Text('Advanced'), selected: _riskFilter == 'advanced', onSelected: (_) => setState(() => _riskFilter = _riskFilter == 'advanced' ? 'all' : 'advanced')),
              FilterChip(label: const Text('Review first'), selected: _riskFilter == 'review', onSelected: (_) => setState(() => _riskFilter = _riskFilter == 'review' ? 'all' : 'review')),
              FilterChip(label: const Text('Keep'), selected: _riskFilter == 'keep', onSelected: (_) => setState(() => _riskFilter = _riskFilter == 'keep' ? 'all' : 'keep')),
            ]),
          ),
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
                          subtitle: Text((system ? 'System package' : 'User package') + ' · ' + (disabled ? 'Disabled' : 'Enabled') + ' · ' + (_guidance[package]?['risk'] as String? ?? 'Not listed')),
                          onTap: () => _showGuidance(item),
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
