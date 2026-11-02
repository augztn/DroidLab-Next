part of 'feature_pages.dart';

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
  bool _installingPlatformTools = false;
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
        _status = ref.read(droidLabSettingsStoreProvider).recoveryNotice ?? '';
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

  Future<void> _installPlatformTools() async {
    if (_installingPlatformTools || _saving) return;
    if (!Platform.isWindows && !Platform.isMacOS) {
      setState(() => _status =
          'Automatic Platform-Tools setup is available on Windows and macOS. On Linux, install Android SDK Platform-Tools with your distribution package manager or Android SDK Manager.');
      return;
    }

    var licenseAccepted = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('Install Android Platform-Tools'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DroidLab will download the official Google Platform-Tools archive directly from dl.google.com and install it in your user profile. The tools are not bundled or redistributed with DroidLab.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Google’s Android SDK License applies. It limits use to developing applications for compatible Android implementations and restricts copying, modification and redistribution of SDK components. Read the full terms before continuing.',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'https://developer.android.com/tools/releases/platform-tools',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Clipboard.setData(const ClipboardData(
                      text: 'https://developer.android.com/tools/releases/platform-tools',
                    )),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Google terms and download page'),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: licenseAccepted,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) => updateDialog(
                    () => licenseAccepted = value ?? false,
                  ),
                  title: const Text('I have read and accept Google’s Android SDK License Agreement.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: licenseAccepted
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Accept and download'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() {
      _installingPlatformTools = true;
      _status = 'Downloading and validating Google Android Platform-Tools…';
    });
    try {
      await ref.read(backendReadyProvider.future);
      const intent = {
        'operation': 'system.platform_tools.install',
        'version': '37.0.1',
        'license_accepted': true,
      };
      final result = await trackOperation(
        ref,
        operation: 'System: install Android Platform-Tools',
        target: 'Local host',
        action: () => ref.read(backendClientProvider).request(
          'system.platform_tools.install',
          {
            ...intent,
            'confirmed': true,
            'confirmation': intent,
          },
          timeout: const Duration(minutes: 5),
        ),
      );
      final toolsResult = await ref.read(backendClientProvider).request(
        'system.tools',
        const {},
      );
      final tools = toolsResult.data['tools'] as Map<String, dynamic>? ?? const {};
      final adb = tools['adb'] as Map<String, dynamic>? ?? const {};
      final fastboot = tools['fastboot'] as Map<String, dynamic>? ?? const {};
      if (adb['available'] != true || fastboot['available'] != true) {
        throw StateError(
          'Platform-Tools were downloaded, but the configured ADB/Fastboot paths still do not resolve. Clear invalid custom tool-path overrides and retry.',
        );
      }
      if (mounted) {
        setState(() => _status =
            'Android Platform-Tools ${result.data['version']} ready. ADB: ${adb['path']} · Fastboot: ${fastboot['path']}');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Platform-Tools installation failed: $error');
    } finally {
      if (mounted) setState(() => _installingPlatformTools = false);
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
      subtitle: 'Appearance and executable paths. Blank tool paths use app-managed tools first, then system PATH.',
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
                  if (Platform.isWindows || Platform.isMacOS) ...[
                    const SizedBox(height: 4),
                    FilledButton.tonalIcon(
                      onPressed: _installingPlatformTools || _saving
                          ? null
                          : _installPlatformTools,
                      icon: _installingPlatformTools
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_installingPlatformTools
                          ? 'Installing Platform-Tools…'
                          : 'Install Android Platform-Tools'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Downloads the official Google tools after license acceptance and installs them per-user. Existing explicit executable overrides remain higher priority.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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

