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
  final _apkPath = TextEditingController();
  final _backupPath = TextEditingController();
  List<String> _apkPaths = const [];
  List<Map<String, dynamic>> _backupEntries = const [];
  final Set<String> _selectedBackups = {};
  List<Map<String, dynamic>> _packages = const [];
  Set<String> _disabled = {};
  final Set<String> _selectedPackages = {};
  int _loadGeneration = 0;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _apkPath.dispose();
    _backupPath.dispose();
    super.dispose();
  }

  Future<void> _browseApk() async {
    const group = XTypeGroup(label: 'Android application packages', extensions: ['apk']);
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isNotEmpty && mounted) {
      setState(() {
        _apkPaths = files.map((file) => file.path).toList(growable: false);
        _apkPath.text = _apkPaths.join('; ');
      });
    }
  }

  Future<void> _installApk() async {
    final serial = _serial;
    final paths = _apkPaths;
    if (_busy || serial == null || paths.isEmpty) return;
    for (final path in paths) {
      final apk = File(path);
      if (!path.toLowerCase().endsWith('.apk') || !await apk.exists() || await apk.length() == 0) {
        if (mounted) setState(() => _error = 'Every selected file must be an existing, non-empty .apk file.');
        return;
      }
    }
    final intent = {'operation': 'adb.install_multiple', 'serial': serial, 'apk_paths': paths};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Install ${paths.length} APK file(s)?'),
        content: Text("Target device: $serial\n\nAndroid will install each selected APK separately. Existing apps are updated when Android signing and install policies allow it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Install')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final result = await trackOperation(
        ref,
        operation: 'Install multiple APKs',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.install_multiple', {
          ...intent, 'confirmed': true, 'confirmation': intent,
        }, timeout: const Duration(minutes: 30)),
        successSummary: (_) => 'APK installation completed on $serial.',
      );
      if (mounted) setState(() => _notice = result.data['output']?.toString().trim().isNotEmpty == true
          ? result.data['output'].toString() : '${result.data['installed_count'] ?? 0} installed, ${result.data['failed_count'] ?? 0} failed. See output for details.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _serial == serial) await _load();
  }

  Future<void> _backupApp(Map<String, dynamic> item) async {
    final serial = _serial;
    final package = item['package'] as String;
    if (_busy || serial == null || item['installed'] == false) return;
    final destination = await getDirectoryPath();
    if (destination == null || !mounted) return;
    final intent = {'operation': 'adb.backup', 'serial': serial, 'package': package, 'destination_path': destination};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Back up app APKs?'),
        content: Text('Back up the base APK and all split APKs for $package to:\n$destination\n\nPrivate app data, accounts and settings are not included.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Back up')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final result = await trackOperation(
        ref, operation: 'Back up app APKs', target: serial,
        action: () => ref.read(backendClientProvider).request('adb.backup', {
          ...intent, 'confirmed': true, 'confirmation': intent,
        }, timeout: const Duration(minutes: 30)),
        successSummary: (_) => 'App APK backup completed.',
      );
      if (mounted) setState(() => _notice = 'Backup saved to ${result.data['backup_path'] ?? destination}.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupSelected() async {
    final serial = _serial;
    if (_busy || serial == null || _selectedPackages.isEmpty) return;
    final packages = _selectedPackages.where((package) =>
      _packages.any((item) => item['package'] == package && item['installed'] != false)
    ).toList()..sort();
    if (packages.isEmpty) {
      setState(() => _error = 'Select at least one installed package to back up.');
      return;
    }
    final destination = await getDirectoryPath();
    if (destination == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Back up ${packages.length} app(s)?'),
        content: Text(
          'Save the base APK and split APKs for each selected app to:\n$destination\n\n'
          'Private app data, accounts and settings are not included. '
          'Each app is saved separately; failures will not stop the remaining backups.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Back up selected')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    final succeeded = <String>[];
    final failed = <String, String>{};
    try {
      for (final package in packages) {
        if (!mounted) return;
        final intent = {
          'operation': 'adb.backup',
          'serial': serial,
          'package': package,
          'destination_path': destination,
        };
        try {
          await trackOperation(
            ref,
            operation: 'Back up app APKs',
            target: serial,
            action: () => ref.read(backendClientProvider).request('adb.backup', {
              ...intent, 'confirmed': true, 'confirmation': intent,
            }, timeout: const Duration(minutes: 30)),
            successSummary: (_) => 'APK backup completed for $package.',
          );
          succeeded.add(package);
        } catch (error) {
          if (error is BackendException && error.code == 'cancelled') {
            failed[package] = error.toString();
            break;
          }
          failed[package] = error.toString();
        }
      }
      if (mounted) {
        setState(() {
          final summary = '${succeeded.length} backed up, ${failed.length} failed. Saved under $destination.';
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
  }

  Future<void> _browseBackup() async {
    final directory = await getDirectoryPath();
    if (directory == null || !mounted) return;
    final root = Directory(directory);
    final entries = <Map<String, dynamic>>[];
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory || await Link(entity.path).exists()) continue;
        final manifestFile = File('${entity.path}${Platform.pathSeparator}manifest.json');
        if (await Link(manifestFile.path).exists() || !await manifestFile.exists()) continue;
        try {
          final decoded = jsonDecode(await manifestFile.readAsString());
          if (decoded is! Map<String, dynamic> ||
              decoded['schema_version'] != 1 ||
              decoded['package'] is! String ||
              decoded['files'] is! List ||
              (decoded['files'] as List).isEmpty) continue;
          final package = decoded['package'] as String;
          final files = (decoded['files'] as List).whereType<Map<String, dynamic>>().toList();
          if (files.isEmpty || files.length != (decoded['files'] as List).length) continue;
          var valid = true;
          for (final item in files) {
            final name = item['file'];
            if (name is! String || name.isEmpty ||
                name != name.split(Platform.pathSeparator).last ||
                !name.toLowerCase().endsWith('.apk')) {
              valid = false;
              break;
            }
            final apk = File('${entity.path}${Platform.pathSeparator}$name');
            if (await Link(apk.path).exists() || !await apk.exists() || await apk.length() == 0) {
              valid = false;
              break;
            }
          }
          if (!valid) continue;
          entries.add({
            'package': package,
            'path': entity.path,
            'apk_count': files.length,
            'created_at': decoded['created_at'],
          });
        } on FormatException {
          continue;
        } on FileSystemException {
          continue;
        }
      }
      entries.sort((a, b) => (a['package'] as String).compareTo(b['package'] as String));
      if (!mounted) return;
      setState(() {
        _backupPath.text = directory;
        _backupEntries = entries;
        _selectedBackups.clear();
        _error = null;
        _notice = entries.isEmpty
            ? 'No valid DroidLab app backups found in this folder.'
            : 'Found ${entries.length} app backup(s). Select the apps you want to restore.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not scan backup folder: $error');
    }
  }

  Future<void> _restoreSelectedBackups() async {
    final serial = _serial;
    final selected = _backupEntries.where((entry) =>
      _selectedBackups.contains(entry['path'] as String)).toList();
    if (_busy || serial == null || selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore ${selected.length} app(s)?'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Target device: $serial'),
              const SizedBox(height: 8),
              const Text('Each app backup is integrity-checked and installed separately. Failures do not stop the remaining apps. Private app data, accounts and settings are not included.'),
              const SizedBox(height: 12),
              for (final entry in selected) Text('• ${entry['package']}'),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore selected')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    final restored = <String>[];
    final failed = <String, String>{};
    try {
      for (final entry in selected) {
        if (!mounted) return;
        final package = entry['package'] as String;
        final backupPath = entry['path'] as String;
        final intent = {'operation': 'adb.restore', 'serial': serial, 'backup_path': backupPath};
        try {
          await trackOperation(
            ref,
            operation: 'Restore app backup · $package',
            target: serial,
            action: () => ref.read(backendClientProvider).request('adb.restore', {
              ...intent, 'confirmed': true, 'confirmation': intent,
            }, timeout: const Duration(minutes: 30)),
            successSummary: (_) => 'Restored $package.',
          );
          restored.add(package);
        } catch (error) {
          failed[package] = error.toString();
          if (error is BackendException && error.code == 'cancelled') break;
        }
      }
      if (mounted) {
        setState(() {
          _selectedBackups.removeWhere((path) => selected.any((entry) =>
            entry['path'] == path && restored.contains(entry['package'])));
          final summary = '${restored.length} restored, ${failed.length} failed.';
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
    if (mounted && _serial == serial) await _load();
  }

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
        if (shouldSkipDebloatAction(
          action: action,
          installed: installed,
          disabled: _disabled.contains(package),
        )) {
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

    return _PageFrame(
      title: 'ADB App Manager',
      subtitle: 'Inspect installed packages. Every package change requires explicit confirmation.',
      actions: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: _serial,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Authorized ADB device',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: serials.map((value) => DropdownMenuItem(
              value: value,
              child: Text(value, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: _busy ? null : (value) => setState(() {
              _loadGeneration++;
              _serial = value;
              _packages = const [];
              _disabled = {};
              _recommendations = {};
              _selectedPackages.clear();
            }),
          ),
        ),
        SizedBox(
          width: 104,
          child: TextFormField(
            initialValue: '$_userId',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Android user ID',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 0 && parsed <= 2147483647 && !_busy) {
                setState(() {
                  _loadGeneration++;
                  _userId = parsed;
                  _packages = const [];
                  _disabled = {};
                  _recommendations = {};
                  _selectedPackages.clear();
                });
              }
            },
          ),
        ),
        FilledButton.icon(
          onPressed: _serial == null || _busy ? null : _load,
          icon: const Icon(Icons.list, size: 18),
          label: const Text('Load packages'),
        ),
        IconButton(
          onPressed: _busy || _serial == null ? null : _load,
          tooltip: 'Refresh packages',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final installPanel = Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.install_mobile, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('APK installation', style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Install one or more APK files on the selected device. Each file is processed separately.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _apkPath,
                    readOnly: true,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Selected APK files',
                      hintText: 'No APK files selected',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.insert_drive_file_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy || _serial == null ? null : _browseApk,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Browse APKs'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || _serial == null || _apkPaths.isEmpty ? null : _installApk,
                        icon: const Icon(Icons.install_mobile, size: 18),
                        label: const Text('Install'),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Row(children: [
                    Icon(Icons.backup_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Restore app backups', style: Theme.of(context).textTheme.titleSmall)),
                    if (_backupEntries.isNotEmpty)
                      Text('${_backupEntries.length} found', style: Theme.of(context).textTheme.labelSmall),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _backupPath,
                    readOnly: true,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Backup parent folder',
                      hintText: 'Choose the folder containing app backup folders',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _busy || _serial == null ? null : _browseBackup,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Scan backup folder'),
                    )),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _busy || _serial == null || _selectedBackups.isEmpty
                          ? null : _restoreSelectedBackups,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: Text('Restore (${_selectedBackups.length})'),
                    ),
                  ]),
                  if (_backupEntries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('${_selectedBackups.length} selected', style: Theme.of(context).textTheme.labelMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() {
                          if (_selectedBackups.length == _backupEntries.length) {
                            _selectedBackups.clear();
                          } else {
                            _selectedBackups
                              ..clear()
                              ..addAll(_backupEntries.map((entry) => entry['path'] as String));
                          }
                        }),
                        child: Text(_selectedBackups.length == _backupEntries.length
                            ? 'Clear' : 'Select all'),
                      ),
                    ]),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _backupEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _backupEntries[index];
                          final backup = entry['path'] as String;
                          final selected = _selectedBackups.contains(backup);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selected,
                            onChanged: _busy ? null : (value) => setState(() {
                              if (value == true) {
                                _selectedBackups.add(backup);
                              } else {
                                _selectedBackups.remove(backup);
                              }
                            }),
                            title: Text(entry['package'] as String,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${entry['apk_count']} APK file(s)'),
                          );
                        },
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Choose the parent backup folder to list its backed-up apps.',
                        style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (_serial == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Select an authorized ADB device above to enable installation and restore.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (_apkPaths.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${_apkPaths.length} APK file(s) selected',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
            ),
          );

          final packageListHeight = (constraints.maxHeight * 0.65)
              .clamp(320.0, 720.0)
              .toDouble();

          final packagePanel = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), child: Column(children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded), const SizedBox(width: 8),
            Expanded(child: Text('System-app changes can break Android features. Uninstall for user does not remove the system image APK. Package guidance is device-dependent; no package is automatically marked safe.', style: Theme.of(context).textTheme.bodySmall)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search package IDs', border: OutlineInputBorder()),
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
                  onSelected: (_) => setState(() => _riskFilter = filter.$1),
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
                OutlinedButton.icon(
                  onPressed: _busy || _serial == null || _selectedPackages.isEmpty
                      ? null
                      : _backupSelected,
                  icon: const Icon(Icons.backup_outlined, size: 17),
                  label: const Text('Back up selected'),
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
        SizedBox(height: packageListHeight, child: _busy
          ? const Center(child: CircularProgressIndicator())
          : _serial == null
              ? const _EmptyPanel(icon: Icons.usb_off, title: 'Select an authorized device', message: 'Connect a phone, enable USB debugging, authorize it, then refresh devices.')
              : _packages.isEmpty
                  ? const _EmptyPanel(icon: Icons.apps, title: 'No package inventory loaded', message: 'Load packages to inspect the selected Android user.')
                  : LayoutBuilder(builder: (context, constraints) {
                const selectWidth = 44.0;
                const packageWidth = 300.0;
                const functionWidth = 340.0;
                const actionsWidth = 112.0;
                const minTableWidth = selectWidth + packageWidth + functionWidth +
                    actionsWidth + 24;
                final tableWidth = constraints.maxWidth < minTableWidth
                    ? minTableWidth : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        child: Row(children: [
                          SizedBox(width: selectWidth, child: Text('Select', maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
                          SizedBox(width: packageWidth, child: Text('Package Identifier / Label', maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
                          SizedBox(width: functionWidth, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('Package details', maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)))),
                          SizedBox(width: actionsWidth, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('Actions', maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)))),
                        ]),
                      ),
                      Expanded(child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final item = visible[index];
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
                          final state = !installed ? 'Not installed' : disabled ? 'Disabled' : 'Enabled';
                          final stateColor = !installed
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : disabled
                                  ? Theme.of(context).colorScheme.secondary
                                  : Theme.of(context).colorScheme.tertiary;
                          final riskColor = riskLower.startsWith('low')
                              ? Theme.of(context).colorScheme.tertiary
                              : riskLower.startsWith('critical') || riskLower.startsWith('high')
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.secondary;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              SizedBox(width: selectWidth, child: Checkbox(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  SelectableText(package, maxLines: 1,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                    )),
                                ])),
                              ])),
                              SizedBox(width: functionWidth, child: Padding(
                                padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(function, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 0,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Tooltip(
                                          message: 'View risk explanation and removal impact',
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(20),
                                              onTap: () => _showGuidance(item),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: riskColor.withValues(alpha: 0.12),
                                                  border: Border.all(color: riskColor.withValues(alpha: 0.35)),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.info_outline, size: 12, color: riskColor),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Risk · $risk',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                        fontSize: 11.5,
                                                        color: riskColor,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: stateColor.withValues(alpha: 0.12),
                                            border: Border.all(color: stateColor.withValues(alpha: 0.35)),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            state,
                                            maxLines: 1,
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              fontSize: 11.5,
                                              color: stateColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )),
                              SizedBox(width: actionsWidth, child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (!installed)
                                  IconButton(
                                    tooltip: 'Restore for this user',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: _busy ? null : () => _apply(item, 'restore'),
                                    icon: const Icon(Icons.restore_rounded, size: 18),
                                  )
                                else if (disabled)
                                  IconButton(
                                    tooltip: 'Enable package',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: _busy ? null : () => _apply(item, 'enable'),
                                    icon: const Icon(Icons.play_circle_outline, size: 18),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Disable package',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: _busy ? null : () => _apply(item, 'disable'),
                                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                                  ),
                                IconButton(
                                  tooltip: 'Back up base and split APKs',
                                  visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                    padding: EdgeInsets.zero,
                                  onPressed: _busy || !installed ? null : () => _backupApp(item),
                                  icon: const Icon(Icons.backup_outlined, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Uninstall for user',
                                  visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                    padding: EdgeInsets.zero,
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
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${visible.length} of ${_packages.length} packages · ${_disabled.length} disabled',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
            ],
          );

          if (constraints.maxWidth >= 1120) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: packagePanel),
                const SizedBox(width: 14),
                SizedBox(
                  width: 370,
                  child: SingleChildScrollView(child: installPanel),
                ),
              ],
            );
          }

          // Keep the whole workflow reachable on compact windows.
          // The package list remains bounded and scrolls independently.
          return SingleChildScrollView(
            primary: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  installPanel,
                  const SizedBox(height: 10),
                  packagePanel,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
