part of 'feature_pages.dart';

class AppManagerPage extends ConsumerStatefulWidget {
  const AppManagerPage({super.key});
  @override
  ConsumerState<AppManagerPage> createState() => _AppManagerPageState();
}

class _AppManagerPageState extends ConsumerState<AppManagerPage> {
  String? _serial;
  int _userId = 0;
  String _query = '';
  List<Map<String, dynamic>> _apps = const [];
  bool _busy = false;
  String? _error;
  String? _notice;
  int _generation = 0;

  Future<void> _load() async {
    final serial = _serial;
    if (serial == null || _busy) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final result = await ref.read(backendClientProvider).request(
        'apps.packages.list', {'serial': serial, 'user_id': _userId});
      final apps = (result.data['packages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) => item['installed'] == true).toList(growable: false);
      if (!mounted || generation != _generation || serial != _serial) return;
      setState(() => _apps = apps);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _installApk() async {
    if (_serial == null || _busy) return;
    const type = XTypeGroup(label: 'Android APK', extensions: ['apk']);
    final file = await openFile(acceptedTypeGroups: [type]);
    if (file == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm APK installation'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Target: $_serial'),
          const SizedBox(height: 8),
          SelectableText(file.path),
          const SizedBox(height: 12),
          const Text('Only install APKs from sources you trust. This may install or update an application on the selected device.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Install APK')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final serial = _serial!;
      final intent = {'operation': 'apps.install', 'serial': serial, 'apk_path': file.path, 'replace': true};
      final result = await trackOperation(
        ref, operation: 'Install APK', target: serial,
        action: () => ref.read(backendClientProvider).request(
          'apps.install', {...intent, 'confirmed': true, 'confirmation': intent},
          timeout: const Duration(minutes: 5)),
      );
      if (mounted) setState(() => _notice = result.data['output']?.toString() ?? 'APK installation completed.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _uninstall(Map<String, dynamic> app) async {
    if (_serial == null || _busy || app['system'] == true) return;
    final package = app['package'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Uninstall application?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(package, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('Target: $_serial · Android user $_userId'),
          const SizedBox(height: 8),
          const Text('This removes the app for this Android user. It does not erase a preinstalled APK from the read-only system image.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Uninstall')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final serial = _serial!;
      final intent = {'operation': 'debloat.package.apply', 'serial': serial,
        'package': package, 'action': 'uninstall', 'user_id': _userId};
      final result = await trackOperation(
        ref, operation: 'Uninstall application', target: serial,
        action: () => ref.read(backendClientProvider).request(
          'debloat.package.apply', {...intent, 'confirmed': true, 'confirmation': intent}),
      );
      if (mounted) setState(() => _notice = result.data['output']?.toString() ?? 'Uninstall completed.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final deviceResult = ref.watch(deviceListProvider);
    final devices = (deviceResult.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((item) => item['transport'] == 'adb' && item['state'] == 'device')
        .toList(growable: false);
    final serials = devices.map((item) => item['serial'] as String).toList();
    if (_serial != null && !serials.contains(_serial)) {
      _serial = null; _apps = const []; _generation++;
    }
    final visible = _apps.where((app) {
      final package = app['package'] as String? ?? '';
      return _query.isEmpty || package.toLowerCase().contains(_query.toLowerCase());
    }).toList(growable: false);

    return _PageFrame(
      title: 'App Manager',
      subtitle: 'Install APKs and manage installed user applications. Package safety analysis lives in Android Debloater.',
      actions: [
        SizedBox(width: 220, child: DropdownButtonFormField<String>(
          initialValue: _serial, isExpanded: true,
          decoration: const InputDecoration(isDense: true, labelText: 'Authorized ADB device',
            border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: serials.map((value) => DropdownMenuItem(value: value,
            child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy ? null : (value) => setState(() {
            _generation++; _serial = value; _apps = const []; _error = null; _notice = null;
          }),
        )),
        FilledButton.icon(onPressed: _serial == null || _busy ? null : _installApk,
          icon: const Icon(Icons.install_mobile_rounded, size: 18), label: const Text('Install APK')),
        OutlinedButton.icon(onPressed: _serial == null || _busy ? null : _load,
          icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh apps')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          const Icon(Icons.info_outline_rounded), const SizedBox(width: 10),
          Expanded(child: Text('App Manager focuses on app installation and user-app removal. System package risk, recommendations, disable/restore guidance and bulk debloating remain in Android Debloater.',
            style: Theme.of(context).textTheme.bodySmall)),
        ]))),
        const SizedBox(height: 10),
        TextField(decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search),
          hintText: 'Search installed package IDs', border: OutlineInputBorder()),
          onChanged: (value) => setState(() => _query = value.trim())),
        if (_error != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_notice != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(_notice!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary))),
        const SizedBox(height: 8),
        Expanded(child: _busy ? const Center(child: CircularProgressIndicator())
          : _serial == null
            ? const _EmptyPanel(icon: Icons.usb_off, title: 'Select an authorized device',
                message: 'Connect a phone, enable USB debugging, authorize it, then select it above.')
            : _apps.isEmpty
              ? const _EmptyPanel(icon: Icons.apps_rounded, title: 'No app inventory loaded',
                  message: 'Refresh apps to load installed applications for the selected Android user.')
              : visible.isEmpty
                ? const _EmptyPanel(icon: Icons.search_off_rounded, title: 'No matching applications',
                    message: 'Try another package name.')
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    itemBuilder: (context, index) {
                      final app = visible[index];
                      final package = app['package'] as String;
                      final system = app['system'] == true;
                      final disabled = app['disabled'] == true;
                      final kind = system ? 'System app' : 'User app';
                      final state = disabled ? 'Disabled' : 'Enabled';
                      return ListTile(
                        leading: _PackageIconBadge(identifier: package),
                        title: Text(package, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$kind · $state'),
                        trailing: system
                          ? const Tooltip(message: 'Use Android Debloater for system-package actions',
                              child: Icon(Icons.shield_outlined))
                          : IconButton(tooltip: 'Uninstall for this user',
                              onPressed: _busy ? null : () => _uninstall(app),
                              icon: const Icon(Icons.delete_outline_rounded)),
                      );
                    },
                  )),
        if (_apps.isNotEmpty) Align(alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.only(top: 6),
            child: Text('${visible.length} of ${_apps.length} installed applications',
              style: Theme.of(context).textTheme.bodySmall))),
      ]),
    );
  }
}
