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
      subtitle: 'Appearance and executable paths. Blank tool paths use bundled tools first, then system PATH.',
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

