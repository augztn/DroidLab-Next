part of 'feature_pages.dart';

class PayloadExtractorPage extends ConsumerStatefulWidget {
  const PayloadExtractorPage({super.key});

  @override
  ConsumerState<PayloadExtractorPage> createState() => _PayloadExtractorPageState();
}

class _PayloadExtractorPageState extends ConsumerState<PayloadExtractorPage> {
  final _source = TextEditingController();
  final _output = TextEditingController();
  final _partitionFilter = TextEditingController();
  final Set<String> _selected = {};
  final List<String> _activityLines = [];
  final List<({String label, String path})> _mountedLocations = [];
  String? _selectedMount;
  StreamSubscription<BackendEvent>? _events;
  List<Map<String, dynamic>> _parts = [];
  String? _cachedPartitionQuery;
  List<Map<String, dynamic>> _cachedVisibleParts = const [];
  String _status = 'Drop an OTA ZIP or payload BIN file here, or enter its path.';
  String _lastSourcePath = '';
  bool _busy = false;
  bool _sha = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    _output.text = '$home${Platform.pathSeparator}DroidLab';
    _source.addListener(_handleSourceChanged);
    _events = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'payload' && mounted) {
        final match = RegExp(r'(\d{1,3})%').firstMatch(event.line);
        final percent = match == null ? null : int.tryParse(match.group(1)!);
        setState(() {
          _activityLines.add(event.line);
          if (percent != null && percent >= 0 && percent <= 100) {
            _progress = percent / 100;
          }
          if (_activityLines.length > 300) {
            _activityLines.removeRange(0, _activityLines.length - 300);
          }
        });
      }
    });
    unawaited(_refreshMountedLocations());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel() ?? Future<void>.value());
    _source.removeListener(_handleSourceChanged);
    _source.dispose();
    _output.dispose();
    _partitionFilter.dispose();
    super.dispose();
  }

  void _handleSourceChanged() {
    final source = _source.text.trim();
    if (source == _lastSourcePath) return;
    _lastSourcePath = source;
    if (!mounted) return;
    setState(() {
      _parts = [];
      _selected.clear();
      _cachedPartitionQuery = null;
      _cachedVisibleParts = const [];
      _status = source.isEmpty
          ? 'Choose an OTA ZIP or payload.bin file.'
          : 'Input changed. Inspect the new payload to load its partitions.';
    });
  }

  void _setSourcePath(String path) {
    if (_source.text == path) return;
    _source.text = path;
  }

  Future<void> _browseSource() async {
    const group = XTypeGroup(label: 'OTA and payload files', extensions: ['zip', 'bin']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) _setSourcePath(file.path);
  }

  Future<void> _browseOutput() async {
    final directory = await getDirectoryPath(confirmButtonText: 'Use output directory');
    if (directory != null && mounted) setState(() => _output.text = directory);
  }

  Future<void> _refreshMountedLocations() async {
    final backendReady = Platform.isWindows
        ? ref.read(backendReadyProvider.future)
        : null;
    final backendClient = Platform.isWindows
        ? ref.read(backendClientProvider)
        : null;
    final roots = <Directory>[];
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      final user = Platform.environment['USER'] ??
          Platform.environment['USERNAME'] ??
          (home.isEmpty ? '' : Directory(home).uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (user.isNotEmpty) {
        roots.add(Directory('/run/media/$user'));
        roots.add(Directory('/media/$user'));
      }
    } else if (Platform.isMacOS) {
      roots.add(Directory('/Volumes'));
    } else if (Platform.isWindows) {
      // Windows removable volumes are queried through GetLogicalDriveStringsW
      // and filtered by GetDriveTypeW == DRIVE_REMOVABLE in the backend.
    }
    final found = <({String label, String path})>[];
    final seen = <String>{};
    if (Platform.isWindows) {
      try {
        await backendReady!;
        if (!mounted) return;
        final result = await backendClient!.request(
          'storage.removable_drives',
          const {},
        );
        final drives = (result.data['drives'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
        for (final drive in drives) {
          final path = drive['path'];
          final label = drive['label'];
          if (path is String && path.isNotEmpty && label is String) {
            found.add((label: label, path: path));
            seen.add(path.toUpperCase());
          }
        }
      } catch (error) {
        if (mounted) {
          setState(() => _status = 'Windows removable-drive scan failed: $error');
        }
        return;
      }
    }
    for (final root in roots) {
      try {
        if (!await root.exists()) continue;
        if (Platform.isWindows && root.path.length <= 3) {
          final key = root.path.toUpperCase();
          if (seen.add(key)) {
            found.add((label: 'Drive $key', path: root.path));
          }
          continue;
        }
        await for (final entity in root.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final path = entity.path;
          if (seen.add(path)) {
            final segments = entity.uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
            final label = segments.isEmpty ? path : segments.last;
            found.add((label: label, path: path));
          }
        }
      } on FileSystemException {
        // Ignore inaccessible mount roots and continue discovering the others.
      }
    }
    found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _mountedLocations
        ..clear()
        ..addAll(found);
      if (_selectedMount == null || !found.any((item) => item.path == _selectedMount)) {
        _selectedMount = found.length == 1 ? found.first.path : null;
      }
      if (found.isEmpty) {
        _status = 'No mounted removable drives found. Use Browse or Choose output.';
      } else {
        _status = 'Found ${found.length} available storage location(s).';
      }
    });
  }

  void _useMountedOutput() {
    final selected = _selectedMount;
    if (selected != null && mounted) setState(() => _output.text = selected);
  }

  Future<void> _browseMountedInput() async {
    final selected = _selectedMount;
    if (selected == null) return;
    final location = await openFile(
      confirmButtonText: 'Select OTA / payload file',
      initialDirectory: selected,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'OTA and payload files', extensions: ['zip', 'bin']),
      ],
    );
    if (location != null && mounted) _setSourcePath(location.path);
  }

  Future<void> _openOutput() async {
    final path = _output.text.trim();
    if (path.isEmpty) return;
    try {
      await Directory(path).create(recursive: true);
      final command = Platform.isWindows ? 'explorer' : Platform.isMacOS ? 'open' : 'xdg-open';
      await Process.start(command, [path], mode: ProcessStartMode.detached);
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not open output directory: ' + error.toString());
    }
  }

  void _drop(DropDoneDetails detail) {
    final candidates = detail.files
        .where((file) {
          final path = file.path.toLowerCase();
          return path.endsWith('.bin') || path.endsWith('.zip');
        })
        .toList(growable: false);
    if (candidates.isEmpty) {
      setState(() => _status = 'Drop a payload.bin file or Android OTA ZIP package.');
      return;
    }
    final chosen = candidates.firstWhere(
      (file) => file.name.toLowerCase() == 'payload.bin',
      orElse: () => candidates.first,
    );
    _setSourcePath(chosen.path);
  }

  Future<void> _inspect() async {
    if (_source.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'payload.inspect',
        {'source_path': _source.text.trim()},
        timeout: const Duration(minutes: 3),
      );
      final parts = (result.data['partitions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _cachedPartitionQuery = null;
        _selected.clear();
        _status = 'Found ' + parts.length.toString() + ' partitions.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    if (_source.text.trim().isEmpty || _output.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final result = await trackOperation(
        ref,
        operation: 'Payload extraction',
        target: _source.text.trim(),
        action: () => ref.read(backendClientProvider).request('payload.extract', {
          'source_path': _source.text.trim(),
          'output_dir': _output.text.trim(),
          'partitions': _selected.toList(),
          'sha256': _sha,
        }, timeout: const Duration(hours: 1)),
        successSummary: (value) =>
            ((value.data['files'] as List<dynamic>? ?? const []).length).toString() + ' image file(s) created.',
      );
      final count = (result.data['files'] as List<dynamic>? ?? const []).length;
      if (mounted) setState(() => _status = 'Created ' + count.toString() + ' image files.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleParts {
    final query = _partitionFilter.text.trim().toLowerCase();
    if (_cachedPartitionQuery == query) return _cachedVisibleParts;
    _cachedPartitionQuery = query;
    _cachedVisibleParts = query.isEmpty
        ? _parts
        : _parts.where((part) =>
            (part['name'] as String).toLowerCase().contains(query)
          ).toList(growable: false);
    return _cachedVisibleParts;
  }

  @override
  Widget build(BuildContext context) {
    final sourcePanel = Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final source = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _TextField(
              controller: _source,
              label: 'INPUT FILE · OTA ZIP or payload.bin',
            )),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Browse for the OTA ZIP or payload.bin input file',
              child: OutlinedButton.icon(
                onPressed: _browseSource,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Browse input'),
              ),
            ),
          ]);
          final output = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _TextField(
              controller: _output,
              label: 'OUTPUT FOLDER · extracted image destination',
            )),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Choose a destination folder for extracted images',
              child: OutlinedButton.icon(
                onPressed: _browseOutput,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Browse output'),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Open the selected output folder in your file manager',
              child: OutlinedButton.icon(
                onPressed: _openOutput,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open folder'),
              ),
            ),
          ]);
          return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: source),
                const SizedBox(width: 16),
                Expanded(child: output),
              ])
            : Column(children: [source, const SizedBox(height: 10), output]);
        }),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final drivePicker = DropdownButtonFormField<String>(
            initialValue: _selectedMount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Mounted removable drive'),
            hint: const Text('Select mounted storage'),
            items: _mountedLocations.map((item) => DropdownMenuItem<String>(
              value: item.path,
              child: Text('${item.label} · ${item.path}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (value) => setState(() => _selectedMount = value),
          );
          final driveActions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.filledTonal(
                tooltip: 'Refresh mounted drives',
                onPressed: _refreshMountedLocations,
                icon: const Icon(Icons.refresh),
              ),
              OutlinedButton(
                onPressed: _selectedMount == null ? null : _useMountedOutput,
                child: const Text('Set as output folder'),
              ),
              OutlinedButton(
                onPressed: _selectedMount == null ? null : _browseMountedInput,
                child: const Text('Choose input from drive'),
              ),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    drivePicker,
                    const SizedBox(height: 8),
                    driveActions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: drivePicker),
                    const SizedBox(width: 8),
                    driveActions,
                  ],
                );
        }),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: _busy ? null : _inspect, child: const Text('Inspect payload')),
          FilledButton.icon(
            onPressed: _busy ? null : _extract,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Extract selected (or all if none selected)'),
          ),
          FilterChip(
            label: const Text('Compute SHA-256 digest'),
            selected: _sha,
            onSelected: (value) => setState(() => _sha = value),
          ),
        ]),
        const SizedBox(height: 10),
        Text(_status, style: Theme.of(context).textTheme.bodySmall),
      ]),
    ));
    final partitionPanel = Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(
            '${_parts.length} partitions · ${_selected.length} selected',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          )),
          TextButton(onPressed: () => setState(() => _selected.addAll(_parts.map((p) => p['name'] as String))),
            child: const Text('Select all')),
          TextButton(onPressed: () => setState(_selected.clear), child: const Text('Select none')),
        ]),
        const SizedBox(height: 8),
        _TextField(controller: _partitionFilter, label: 'Filter partitions', hint: 'boot, vbmeta, system…',
          onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        SizedBox(
          height: 360,
          child: _visibleParts.isEmpty
            ? const Center(child: Text('No partitions match this filter.'))
            : ListView.separated(
                itemCount: _visibleParts.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  final part = _visibleParts[index];
                  final name = part['name'] as String;
                  return CheckboxListTile(
                    dense: true,
                    value: _selected.contains(name),
                    title: Text(name, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                    subtitle: Text('${part['size_bytes']} bytes'),
                    onChanged: _busy ? null : (value) => setState(() {
                      if (value == true) {
                        _selected.add(name);
                      } else {
                        _selected.remove(name);
                      }
                    }),
                  );
                },
              ),
        ),
      ]),
    ));
    final activityPanel = Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Activity Log', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _OutputPanel(output: _activityLines.isEmpty ? _status : _activityLines.join('\n')),
        if (_busy) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _progress),
          if (_progress != null) Text('Extraction progress: ${(_progress! * 100).round()}%'),
        ],
      ]),
    ));
    return _PageFrame(
      title: 'Firmware & OTA Payload Extractor',
      subtitle: 'Isolated staging directory · Rejects empty/symlink artifacts · Atomic non-overwriting publication',
      child: DropTarget(
        onDragDone: _drop,
        child: ListView(children: [
          sourcePanel,
          if (_parts.isNotEmpty) ...[const SizedBox(height: 14), partitionPanel],
          const SizedBox(height: 14),
          activityPanel,
        ]),
      ),
    );
  }
}
