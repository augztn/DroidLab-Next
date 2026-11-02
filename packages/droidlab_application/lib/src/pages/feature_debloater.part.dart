part of 'feature_pages.dart';

class _PackageIconBadge extends StatelessWidget {
  const _PackageIconBadge({required this.identifier});
  final String identifier;

  @override
  Widget build(BuildContext context) {
    final key = identifier.toLowerCase();
    final (icon, color) = key.contains('magisk')
        ? (Icons.shield_outlined, const Color(0xFF35C98A))
        : key.contains('lawnchair') || key.contains('systemui')
            ? (Icons.grid_view_rounded, const Color(0xFFA78BFA))
            : key.contains('termux') || key.contains('adbd')
                ? (Icons.terminal_rounded, const Color(0xFFF5A524))
                : key.contains('assistantscreen') || key.contains('breeno')
                    ? (Icons.auto_awesome_outlined, const Color(0xFF38BDF8))
                    : key.contains('themestore')
                        ? (Icons.palette_outlined, const Color(0xFFF472B6))
                        : key.contains('googleassistant')
                            ? (Icons.mic_none_rounded, const Color(0xFF60A5FA))
                            : key.contains('gearhead') || key.contains('auto')
                                ? (Icons.directions_car_outlined, const Color(0xFF38BDF8))
                                : key.contains('oshare')
                                    ? (Icons.share_outlined, const Color(0xFF34D399))
                                    : key.contains('aod')
                                        ? (Icons.schedule_outlined, const Color(0xFFC084FC))
                                        : key.contains('opencapability') || key.contains('surfaceflinger') || key.contains('composer')
                                            ? (Icons.layers_outlined, const Color(0xFFFBBF24))
                                            : key.contains('soter')
                                                ? (Icons.fingerprint, const Color(0xFFFB923C))
                                                : key.contains('phonemanager') || key.contains('system_server')
                                                    ? (Icons.tune_rounded, const Color(0xFFF87171))
                                                    : key.contains('securitykeyboard')
                                                        ? (Icons.key_outlined, const Color(0xFFFB7185))
                                                        : key.contains('qualcomm') || key.contains('uim')
                                                            ? (Icons.radio_outlined, const Color(0xFF818CF8))
                                                             : key.contains('overlay') || key.contains('rro')
                                                                 ? (Icons.layers_outlined, const Color(0xFF38BDF8))
                                                                 : key.contains('ext.services') || key.contains('android.ext')
                                                                     ? (Icons.extension_outlined, const Color(0xFFA78BFA))
                                                                     : key.contains('bluetooth')
                                                                         ? (Icons.bluetooth, const Color(0xFF60A5FA))
                                                                         : key.contains('camera')
                                                                             ? (Icons.camera_alt_outlined, const Color(0xFFF59E0B))
                                                                             : key.contains('contacts') || key.contains('dialer') || key.contains('phone')
                                                                                 ? (Icons.contacts_outlined, const Color(0xFF34D399))
                                                                                 : key.contains('calendar')
                                                                                     ? (Icons.calendar_month_outlined, const Color(0xFFFB7185))
                                                                                     : key.contains('browser') || key.contains('chrome') || key.contains('webview')
                                                                                         ? (Icons.language_outlined, const Color(0xFF38BDF8))
                                                                                         : key.contains('location') || key.contains('maps')
                                                                                             ? (Icons.location_on_outlined, const Color(0xFF22C55E))
                                                                                             : key.contains('media') || key.contains('music') || key.contains('audio')
                                                                                                 ? (Icons.music_note_outlined, const Color(0xFFC084FC))
                                                                                                 : (key.endsWith('.apk') ? Icons.android : Icons.memory_outlined,
                                                                Theme.of(context).colorScheme.primary);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: color),
    );
  }
}

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
  Set<String> _recommendations = {};
  bool _busy = false;
  List<Map<String, dynamic>> _packages = const [];
  Set<String> _disabled = {};
  final Set<String> _selectedPackages = {};
  int _loadGeneration = 0;
  int _pageIndex = 0;
  int _pageSize = 50;
  String? _error;
  String? _notice;

  Future<void> _load() async {
    final serial = _serial;
    if (serial == null || _busy) return;
    final generation = ++_loadGeneration;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final client = ref.read(backendClientProvider);
      final catalogResult = await client.request('debloat.catalog.list', const {});
      final catalogEntries = catalogResult.data['entries'] as List<dynamic>? ?? const [];
      final guidanceByPackage = <String, Map<String, dynamic>>{};
      for (final value in catalogEntries.whereType<Map<String, dynamic>>()) {
        final package = value['package'];
        if (package is String && package.isNotEmpty) {
          guidanceByPackage[package] = value;
        }
      }
      final recommendationPackages = (catalogResult.data['recommendations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) => item['package'] is String)
          .map((item) => item['package'] as String)
          .toSet();
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
        _selectedPackages.removeWhere((package) =>
          !packages.any((item) => item['package'] == package));
        _recommendations = recommendationPackages;
        _guidance = guidanceByPackage;
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

  Future<void> _applyPackage(String package, String action) async {
    final serial = _serial;
    if (serial == null) throw StateError('Select an authorized ADB device.');
    await trackOperation(
      ref,
      operation: 'Android package $action',
      target: serial,
      action: () async {
        final intent = {
          'operation': 'debloat.package.apply',
          'serial': serial,
          'package': package,
          'action': action,
          'user_id': _userId,
        };
        return ref.read(backendClientProvider).request(
          'debloat.package.apply',
          {...intent, 'confirmed': true, 'confirmation': intent},
        );
      },
    );
  }

  Future<bool> _confirmPackageAction({
    required List<String> packages,
    required String action,
  }) async {
    final label = switch (action) {
      'disable' => 'Disable',
      'enable' => 'Enable',
      'restore' => 'Restore for user',
      _ => 'Uninstall for user',
    };
    final explanation = switch (action) {
      'uninstall' => 'Each selected package will be uninstalled for Android user $_userId. This does not remove APKs from read-only system partitions.',
      'disable' => 'Each selected package will be disabled for Android user $_userId.',
      'enable' => 'Each selected disabled package will be enabled for Android user $_userId.',
      'restore' => 'Android will reinstall each selected package for this user using the copy already present in the system image. This cannot restore an APK removed from the system image.',
      _ => 'Unsupported package action.',
    };
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label ${packages.length} packages?'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Target: ${_serial ?? 'No device'} · user $_userId'),
                const SizedBox(height: 8),
                Text(explanation),
                const SizedBox(height: 12),
                const Text('Every package will be checked individually. The batch is not transactional: if one operation fails, the remaining packages will still be attempted.'),
                const SizedBox(height: 12),
                Text('Selected packages', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final package in packages)
                  SelectableText(package, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('$label selected'),
          ),
        ],
      ),
    ) == true;
  }

  Future<void> _apply(Map<String, dynamic> item, String action) async {
    if (_busy) return;
    final package = item['package'] as String;
    final confirmed = await _confirmPackageAction(
      packages: [package],
      action: action,
    );
    if (!confirmed || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await _applyPackage(package, action);
      if (mounted) setState(() => _selectedPackages.remove(package));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _applySelected(String action) async {
    if (_busy || _serial == null || _selectedPackages.isEmpty) return;
    final packages = _selectedPackages.toList()..sort();
    final confirmed = await _confirmPackageAction(
      packages: packages,
      action: action,
    );
    if (!confirmed || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    final succeeded = <String>[];
    final skipped = <String>[];
    final failed = <String, String>{};
    try {
      var cancelled = false;
      // Stop at the first explicit cancellation; never dispatch later mutations.
      for (final package in packages) {
        if (!mounted) return;
        Map<String, dynamic>? item;
        for (final candidate in _packages) {
          if (candidate['package'] == package) {
            item = candidate;
            break;
          }
        }
        final installed = item?['installed'] != false;
        if ((action == 'disable' && _disabled.contains(package)) ||
            (action == 'enable' && !_disabled.contains(package)) ||
            (action == 'restore' && installed)) {
          skipped.add(package);
          continue;
        }
        try {
          await _applyPackage(package, action);
          succeeded.add(package);
        } catch (error) {
          if (error is BackendException && error.code == 'cancelled') {
            failed[package] = error.toString();
            cancelled = true;
            break;
          }
          failed[package] = error.toString();
        }
      }
      if (mounted) {
        setState(() {
          _selectedPackages.removeAll([...succeeded, ...skipped]);
          final summary = '${succeeded.length} succeeded, ${skipped.length} skipped, ${failed.length} failed'
              '${cancelled ? ' · stopped after cancellation' : ''}.';
          if (failed.isEmpty) {
            _notice = summary;
          } else {
            _error = '$summary First failure: ${failed.entries.first.key}: ${failed.entries.first.value}';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  void _selectVisible(List<Map<String, dynamic>> visible) {
    final packages = visible.map((item) => item['package'] as String);
    setState(() => _selectedPackages.addAll(packages));
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
      if (_riskFilter == 'recommended' && !_recommendations.contains(package)) return false;
      if (_riskFilter == 'low' && !risk.startsWith('low')) return false;
      if (_riskFilter == 'conditional' && !risk.startsWith('conditional')) return false;
      if (_riskFilter == 'review' && !(risk.contains('review') || risk.contains('unclear') || risk.contains('not listed'))) return false;
      if (_riskFilter == 'critical' && !(risk.contains('critical') || risk.startsWith('high') || risk.contains('keep'))) return false;
      if (_filter == 'system' && !system) return false;
      if (_filter == 'user' && system) return false;
      final query = _query.trim().toLowerCase();
      return query.isEmpty || package.toLowerCase().contains(query);
    }).toList(growable: false);
    final pageCount = visible.isEmpty ? 1 : (visible.length / _pageSize).ceil();
    final safePageIndex = _pageIndex.clamp(0, pageCount - 1);
    final pageStart = safePageIndex * _pageSize;
    final pageItems = visible.skip(pageStart).take(_pageSize).toList(growable: false);

    return _PageFrame(
      title: 'Android Debloater Workspace',
      subtitle: 'Inspect installed packages. Every package change requires explicit confirmation.',
      actions: [
        IconButton(onPressed: _busy || _serial == null ? null : _load, tooltip: 'Refresh packages', icon: const Icon(Icons.refresh)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Wrap(
          spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 250, child: DropdownButtonFormField<String>(
              initialValue: _serial,
              decoration: const InputDecoration(isDense: true, labelText: 'Authorized ADB device', border: OutlineInputBorder()),
              items: serials.map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _busy ? null : (value) => setState(() { _loadGeneration++; _serial = value; _packages = const []; _disabled = {}; _recommendations = {}; _selectedPackages.clear(); }),
            )),
            SizedBox(width: 130, child: TextFormField(
              initialValue: '0', keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, labelText: 'Android user ID', border: OutlineInputBorder()),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 0 && parsed <= 2147483647 && !_busy) {
                  setState(() { _loadGeneration++; _userId = parsed; _packages = const []; _disabled = {}; _recommendations = {}; _selectedPackages.clear(); });
                }
              },
            )),
            FilledButton.icon(onPressed: _serial == null || _busy ? null : _load, icon: const Icon(Icons.list), label: const Text('Load packages')),
          ],
        ))),
        const SizedBox(height: 6),
        Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), child: Column(children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded), const SizedBox(width: 8),
            Expanded(child: Text('System-app changes can break Android features. Uninstall for user does not remove the system image APK. Package guidance is device-dependent; no package is automatically marked safe.', style: Theme.of(context).textTheme.bodySmall)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search package IDs', border: OutlineInputBorder()),
              onChanged: (value) => setState(() { _query = value; _pageIndex = 0; }),
            )),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'user', child: Text('User apps')),
                DropdownMenuItem(value: 'system', child: Text('System apps')),
              ],
              onChanged: (value) => setState(() { _filter = value ?? 'all'; _pageIndex = 0; }),
            ),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 0, children: [
              for (final filter in const [
                ('all', 'All Risks'),
                ('recommended', 'Recommended'),
                ('low', 'Low Risk'),
                ('conditional', 'Conditional'),
                ('review', 'Review First'),
                ('critical', 'Critical'),
              ])
                FilterChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(filter.$2),
                  selected: _riskFilter == filter.$1,
                  onSelected: (_) => setState(() { _riskFilter = filter.$1; _pageIndex = 0; }),
                ),
            ]),
          ),
        ]))),
        if (_packages.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${_selectedPackages.length} selected',
                    style: Theme.of(context).textTheme.labelLarge),
                TextButton.icon(
                  onPressed: _busy || visible.isEmpty ? null : () => _selectVisible(visible),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('Select visible'),
                ),
                TextButton(
                  onPressed: _busy || _selectedPackages.isEmpty
                      ? null
                      : () => setState(_selectedPackages.clear),
                  child: const Text('Clear selection'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _selectedPackages.isEmpty
                      ? null
                      : () => _applySelected('disable'),
                  icon: const Icon(Icons.pause_circle_outline, size: 17),
                  label: const Text('Disable selected'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _selectedPackages.isEmpty
                      ? null
                      : () => _applySelected('enable'),
                  icon: const Icon(Icons.play_circle_outline, size: 17),
                  label: const Text('Enable selected'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _selectedPackages.isEmpty
                      ? null
                      : () => _applySelected('restore'),
                  icon: const Icon(Icons.restore_rounded, size: 17),
                  label: const Text('Restore selected'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || _selectedPackages.isEmpty
                      ? null
                      : () => _applySelected('uninstall'),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('Uninstall selected'),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_notice != null) Padding(padding: const EdgeInsets.all(8), child: Text(_notice!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary))),
        const SizedBox(height: 4),
        Expanded(child: _busy
          ? const Center(child: CircularProgressIndicator())
          : _serial == null
              ? const _EmptyPanel(icon: Icons.usb_off, title: 'Select an authorized device', message: 'Connect a phone, enable USB debugging, authorize it, then refresh devices.')
              : _packages.isEmpty
                  ? const _EmptyPanel(icon: Icons.apps, title: 'No package inventory loaded', message: 'Load packages to inspect the selected Android user.')
                  : LayoutBuilder(builder: (context, constraints) {
                const selectWidth = 40.0;
                const packageWidth = 270.0;
                const functionWidth = 205.0;
                const riskWidth = 125.0;
                const stateWidth = 105.0;
                const guidanceWidth = 82.0;
                const actionsWidth = 88.0;
                const minTableWidth = selectWidth + packageWidth + functionWidth +
                    riskWidth + stateWidth + guidanceWidth + actionsWidth + 24;
                final tableWidth = constraints.maxWidth < minTableWidth
                    ? minTableWidth : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        child: const Row(children: [
                          SizedBox(width: selectWidth, child: Text('Select', maxLines: 1, softWrap: false)),
                          SizedBox(width: packageWidth, child: Text('Package Identifier / Label', maxLines: 1, softWrap: false)),
                          SizedBox(width: functionWidth, child: Text('OEM / Function', maxLines: 1, softWrap: false)),
                          SizedBox(width: riskWidth, child: Text('Advisory Risk', maxLines: 1, softWrap: false)),
                          SizedBox(width: stateWidth, child: Text('User State', maxLines: 1, softWrap: false)),
                          SizedBox(width: guidanceWidth, child: Text('Guidance', maxLines: 1, softWrap: false)),
                          SizedBox(width: actionsWidth, child: Text('Actions', maxLines: 1, softWrap: false)),
                        ]),
                      ),
                      Expanded(child: ListView.separated(
                        itemCount: pageItems.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final item = pageItems[index];
                          final package = item['package'] as String;
                          final system = item['system'] == true;
                          final disabled = _disabled.contains(package);
                          final installed = item['installed'] != false;
                          final guidance = _guidance[package] ?? const <String, dynamic>{};
                          final app = guidance['app']?.toString() ?? package;
                          final function = guidance['function']?.toString() ??
                              (system ? 'System package · review dependencies' : 'Installed user application');
                          final risk = guidance['risk']?.toString() ?? 'Not listed';
                          final riskLower = risk.toLowerCase();
                          final riskColor = riskLower.startsWith('low')
                              ? Theme.of(context).colorScheme.tertiary
                              : riskLower.startsWith('critical') || riskLower.startsWith('high')
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.secondary;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              SizedBox(width: selectWidth, child: Checkbox(
                                value: _selectedPackages.contains(package),
                                onChanged: _busy ? null : (selected) => setState(() {
                                  if (selected == true) {
                                    _selectedPackages.add(package);
                                    _error = null;
                                  } else {
                                    _selectedPackages.remove(package);
                                    _error = null;
                                  }
                                }),
                              )),
                              SizedBox(width: packageWidth, child: Row(children: [
                                _PackageIconBadge(identifier: package),
                                const SizedBox(width: 9),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(app, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  SelectableText(package, maxLines: 1,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                    )),
                                ])),
                              ])),
                              SizedBox(width: functionWidth, child: Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Text(function, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                              )),
                              SizedBox(width: riskWidth, child: Text(risk, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: riskColor))),
                              SizedBox(width: stateWidth, child: Text(
                                !installed ? 'not installed' : disabled ? 'disabled' : 'enabled',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'))),
                              SizedBox(width: guidanceWidth, child: TextButton(
                                onPressed: () => _showGuidance(item),
                                child: const Text('Explain'),
                              )),
                              SizedBox(width: actionsWidth, child: Row(children: [
                                if (!installed)
                                  IconButton(
                                    tooltip: 'Restore for this user',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy ? null : () => _apply(item, 'restore'),
                                    icon: const Icon(Icons.restore_rounded, size: 18),
                                  )
                                else if (disabled)
                                  IconButton(
                                    tooltip: 'Enable package',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy ? null : () => _apply(item, 'enable'),
                                    icon: const Icon(Icons.play_circle_outline, size: 18),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Disable package',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy ? null : () => _apply(item, 'disable'),
                                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                                  ),
                                IconButton(
                                  tooltip: 'Uninstall for user',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _busy || !installed ? null : () => _apply(item, 'uninstall'),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                ),
                              ])),
                            ]),
                          );
                        },
                      )),
                    ]),
                  ),
                );
              })),
        if (_packages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(child: Text(
                '${visible.isEmpty ? 0 : pageStart + 1}–${(pageStart + pageItems.length)} of ${visible.length} packages · ${_disabled.length} disabled',
                style: Theme.of(context).textTheme.bodySmall,
              )),
              const Text('Rows', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: const [25, 50, 100].map((size) =>
                  DropdownMenuItem(value: size, child: Text('$size'))).toList(),
                onChanged: (size) => setState(() { _pageSize = size ?? 50; _pageIndex = 0; }),
              ),
              IconButton(
                tooltip: 'Previous page',
                visualDensity: VisualDensity.compact,
                onPressed: safePageIndex == 0 ? null : () => setState(() => _pageIndex--),
                icon: const Icon(Icons.chevron_left, size: 19),
              ),
              Text('${safePageIndex + 1} / $pageCount', style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                onPressed: safePageIndex >= pageCount - 1 ? null : () => setState(() => _pageIndex++),
                icon: const Icon(Icons.chevron_right, size: 19),
              ),
            ]),
          ),
      ]),
    );
  }
}
