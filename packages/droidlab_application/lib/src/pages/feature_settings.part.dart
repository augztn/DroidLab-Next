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
  String _themeMode = 'dark';
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
        _themeMode = settings.themeMode;
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
        themeMode: _themeMode,
        pythonPath: _python.text.trim(),
        backendPath: _backend.text.trim(),
        adbPath: _adb.text.trim(),
        fastbootPath: _fastboot.text.trim(),
        payloadDumperPath: _payloadDumper.text.trim(),
      );
      await ref.read(droidLabSettingsProvider.notifier).saveSettings(settings);
      if (mounted) setState(() => _status =
          'Settings saved. Python/backend changes restart the managed backend automatically; device-tool paths are read by the backend on the next command.');
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

  Widget _themeChoice(BuildContext context, String value, String title, String token, IconData icon) {
    final selected = _theme == value;
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _theme = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.09) : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 1.4 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? colors.primary : colors.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(token, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant, fontFamily: 'monospace')),
          ])),
        ]),
      ),
    );
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
    final appearance = Card(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appearance & Theme Identity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Choose a color palette and surface appearance for DroidLab.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _saving || !_loaded ? null : () async {
              final next = _themeMode == 'dark' ? 'light' : 'dark';
              setState(() => _themeMode = next);
              try {
                final current = await ref.read(droidLabSettingsProvider.future);
                await ref.read(droidLabSettingsProvider.notifier).saveSettings(current.copyWith(themeMode: next));
                if (mounted) setState(() => _status = 'Appearance updated.');
              } catch (error) {
                if (mounted) setState(() {
                  _themeMode = next == 'dark' ? 'light' : 'dark';
                  _status = 'Could not update appearance: $error';
                });
              }
            },
            icon: Icon(_themeMode == 'dark' ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 17),
            label: Text(_themeMode == 'dark' ? 'Switch to Light Surface' : 'Switch to Dark Surface'),
          ),
        ]),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final themes = const [
            ('cyberpunk_glass', 'Cyberpunk Glass', 'cyberpunk_glass', Icons.auto_awesome_outlined),
            ('standard_dark', 'Standard Dark', 'standard_dark', Icons.contrast),
            ('oled_black', 'OLED Black', 'oled_black', Icons.dark_mode_outlined),
          ];
          return compact
            ? Column(children: [
                for (final item in themes) Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _themeChoice(context, item.$1, item.$2, item.$3, item.$4),
                ),
              ])
            : Row(children: [
                for (var i = 0; i < themes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _themeChoice(context, themes[i].$1, themes[i].$2, themes[i].$3, themes[i].$4)),
                ],
              ]);
        }),
      ]),
    ));
    final tools = Card(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Executable Overrides & Platform-Tools Bootstrap',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('Blank overrides use app-managed tools first, then system PATH.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _toolField('Python executable', _python, 'python3 or full executable path'),
        _toolField('Backend script', _backend, 'server.py'),
        _toolField('ADB executable', _adb, 'adb'),
        _toolField('Fastboot executable', _fastboot, 'fastboot'),
        _toolField('Payload dumper', _payloadDumper, 'payload-dumper-go'),
        if (Platform.isWindows || Platform.isMacOS) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _installingPlatformTools || _saving ? null : _installPlatformTools,
            icon: _installingPlatformTools
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_installingPlatformTools ? 'Installing Platform-Tools…' : 'Download & Verify Platform-Tools'),
          ),
          const SizedBox(height: 8),
          Text('Downloads official Google tools after license acceptance and installs them per-user. Existing explicit overrides remain higher priority.',
            style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        Text('Configuration: ~/DroidLab/config.json',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ]),
    ));
    return _PageFrame(
      title: 'Workstation Settings (`~/DroidLab/config.json`)',
      subtitle: 'Theme palette tokens, executable override resolution, and Google Platform-Tools per-user bootstrap',
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 950;
              return Column(children: [
                Expanded(child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: SingleChildScrollView(child: appearance)),
                      const SizedBox(width: 24),
                      Expanded(child: SingleChildScrollView(child: tools)),
                    ])
                  : ListView(children: [appearance, const SizedBox(height: 14), tools])),
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
              ]);
            }),
    );
  }
}

