part of 'feature_pages.dart';

class AdbToolkitPage extends ConsumerStatefulWidget {
  const AdbToolkitPage({super.key});

  @override
  ConsumerState<AdbToolkitPage> createState() => _AdbToolkitPageState();
}

class _AdbToolkitPageState extends ConsumerState<AdbToolkitPage> {
  final _serial = TextEditingController();
  final _command = TextEditingController(text: 'getprop ro.build.version.release');
  final _package = TextEditingController();
  final _transferLocal = TextEditingController();
  final _transferRemote = TextEditingController(text: '/sdcard/Download/');
  String _transferDirection = 'push';
  final _bugreport = TextEditingController();
  final _logcatFilters = TextEditingController();
  final _logSavePath = TextEditingController();
  final _logDisplayFilter = TextEditingController();
  final List<String> _logLines = [];
  IOSink? _logcatCaptureSink;
  String? _logcatCapturePath;
  List<String> _pausedLogSnapshot = [];
  bool _logPaused = false;
  StreamSubscription<BackendEvent>? _eventSubscription;
  String? _logcatRequestId;
  String? _logcatManualStopRequestId;
  String _output = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventSubscription = ref.read(backendClientProvider).events.listen((event) {
      if (event is BackendOutput && event.stream == 'logcat' && mounted) {
        try {
          _logcatCaptureSink?.writeln(event.line);
        } catch (_) {
          // A stop/dispose may close the file sink while the last event is in flight.
        }
        setState(() {
          _logLines.add(event.line);
          if (_logLines.length > 500) {
            _logLines.removeRange(0, _logLines.length - 500);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    final logcatRequestId = _logcatRequestId;
    if (logcatRequestId != null) {
        unawaited(ref.read(backendClientProvider).cancel(logcatRequestId));
    }
    unawaited(_closeLogcatCapture());
    unawaited(_eventSubscription?.cancel() ?? Future<void>.value());
    _serial.dispose();
    _command.dispose();
    _package.dispose();
    _transferLocal.dispose();
    _transferRemote.dispose();
    _bugreport.dispose();
    _logcatFilters.dispose();
    _logSavePath.dispose();
    _logDisplayFilter.dispose();
    super.dispose();
  }

  void _dropCommandPath(DropDoneDetails detail) {
    if (detail.files.isEmpty) return;
    final path = detail.files.first.path;
    final quoted = '"${path.replaceAll('"', r'\"')}"';
    final current = _command.text.trim();
    setState(() {
      _command.text = current.isEmpty ? quoted : '$current $quoted';
      _command.selection = TextSelection.collapsed(offset: _command.text.length);
      _output = 'Inserted dropped file path into the command field: $path';
    });
  }

  Future<void> _refreshDevices() async {
    ref.invalidate(deviceListProvider);
    try {
      await ref.read(deviceListProvider.future);
      if (mounted) setState(() => _output = 'Device scan completed. Select an ADB or Fastboot target below.');
    } catch (error) {
      if (mounted) setState(() => _output = 'Device scan failed: $error');
    }
  }

  Map<String, dynamic>? _selectedDevice() {
    final data = ref.read(deviceListProvider).valueOrNull;
    final devices = (data?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final device in devices) {
      if (device['serial'] == _serial.text.trim()) return device;
    }
    return null;
  }

  String? _stripHostExecutable(String command, String executable) {
    final trimmed = command.trimLeft();
    if (trimmed.isEmpty) return null;

    // Parse only the first executable token. Quoted paths may contain spaces;
    // unquoted paths are accepted when the executable itself has no spaces.
    final quote = trimmed.startsWith('"') || trimmed.startsWith("'")
        ? trimmed[0]
        : null;
    late final String executableToken;
    late final int tokenEnd;
    if (quote != null) {
      final closingQuote = trimmed.indexOf(quote, 1);
      if (closingQuote < 0) return null;
      executableToken = trimmed.substring(1, closingQuote);
      tokenEnd = closingQuote + 1;
    } else {
      final match = RegExp(r'^\S+').firstMatch(trimmed);
      if (match == null) return null;
      executableToken = match.group(0)!;
      tokenEnd = match.end;
    }

    final normalizedPath = executableToken.replaceAll(r'\', '/');
    final basename = normalizedPath.split('/').last.toLowerCase();
    final expected = executable.toLowerCase();
    if (basename != expected && basename != '$expected.exe') return null;

    return trimmed.substring(tokenEnd).trim();
  }

  Future<bool> _confirmCommand({
    required String title,
    required String target,
    required String command,
    required String warning,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + target),
            const SizedBox(height: 8),
            SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            Text(warning),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Execute command')),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _runShell() async {
    final command = _command.text.trim();
    if (command.isEmpty || _busy) return;

    final target = _selectedDevice();
    final serial = target?['serial'] as String?;
    final transport = target?['transport'] as String?;
    final state = target?['state'] as String?;

    final fastbootArguments = _stripHostExecutable(command, 'fastboot');
    if (fastbootArguments != null) {
      final verb = fastbootArguments.split(RegExp(r'\s+')).first.toLowerCase();
      const discovery = {'devices', 'help', '--help', '--version', 'version'};
      final isDiscovery = discovery.contains(verb);
      if (!isDiscovery && (transport != 'fastboot' || serial == null || state != 'fastboot')) {
        setState(() => _output =
            'Select a detected Fastboot device before running a device-targeted Fastboot command. Discovery commands such as fastboot devices do not need a selected device.');
        return;
      }
      if (fastbootArguments.isEmpty) {
        setState(() => _output = 'Enter Fastboot arguments, for example: devices or getvar all.');
        return;
      }
      final fastbootTarget = isDiscovery ? null : serial;
      final fastbootPreview = 'fastboot ' +
          (fastbootTarget == null ? '' : '-s $fastbootTarget ') +
          fastbootArguments;
      final confirmed = await _confirmCommand(
        title: 'Confirm advanced Fastboot command',
        target: fastbootTarget ?? 'host / discovery command',
        command: fastbootPreview,
        warning: isDiscovery
            ? 'This runs a host-side Fastboot discovery/help command and does not target a device.'
            : 'Advanced Fastboot commands can change boot state, erase data, or make the device unbootable. Verify the exact command and device.',
      );
      if (!confirmed) return;
      setState(() => _busy = true);
      try {
        final result = await trackOperation(
          ref,
          operation: 'Advanced Fastboot: ' + fastbootArguments,
          target: fastbootTarget ?? 'host',
          action: () => ref.read(backendClientProvider).request('fastboot.command', {
            'serial': fastbootTarget,
            'command': fastbootArguments,
            'confirmed': true,
            'confirmation': {
              'operation': 'fastboot.command',
              'serial': fastbootTarget,
              'command': fastbootArguments,
            },
          }, timeout: const Duration(minutes: 30)),
        );
        if (mounted) setState(() => _output = result.data['output']?.toString() ??
            result.data.toString());
      } catch (error) {
        if (mounted) setState(() => _output = error.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final adbArguments = _stripHostExecutable(command, 'adb');
    if (adbArguments != null) {
      final args = adbArguments.isEmpty ? 'devices -l' : adbArguments;
      final verb = args.split(RegExp(r'\s+')).first.toLowerCase();
      if (verb == 'reboot') {
        final tokens = args.split(RegExp(r'\s+'));
        final mode = tokens.length > 1 ? tokens[1].toLowerCase() : 'system';
        if (mode == 'recovery' || mode == 'bootloader' || mode == 'system' || mode == 'fastboot') {
          await _reboot(mode);
        } else {
          if (mounted) setState(() => _output =
              'Use reboot, reboot recovery, reboot bootloader, or reboot fastboot.');
        }
        return;
      }
      final selectedAdbSerial = transport == 'adb' ? serial : null;
      final confirmed = await _confirmCommand(
        title: 'Confirm advanced host ADB command',
        target: selectedAdbSerial ?? 'host / discovery command',
        command: 'adb ' + args,
        warning:
            'Host ADB commands are unrestricted. They may install packages, transfer files, modify the selected device, or affect the local ADB server.',
      );
      if (!confirmed) return;
      setState(() => _busy = true);
      try {
        final result = await trackOperation(
          ref,
          operation: 'Advanced ADB: ' + args,
          target: selectedAdbSerial ?? 'host',
          action: () => ref.read(backendClientProvider).request('adb.command', {
            'serial': selectedAdbSerial,
            'command_text': args,
            'confirmed': true,
            'confirmation': {
              'operation': 'adb.command',
              'serial': selectedAdbSerial,
              'command_text': args,
            },
          }, timeout: const Duration(minutes: 30)),
        );
        if (mounted) setState(() => _output = result.data['output']?.toString() ??
            result.data.toString());
      } catch (error) {
        if (mounted) setState(() => _output = error.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    if (transport != 'adb' || state != 'device' || serial == null) {
      setState(() => _output =
          'Select an authorized ADB device for Android shell commands. Host commands must start with adb; Fastboot commands must start with fastboot.');
      return;
    }
    final confirmed = await _confirmCommand(
      title: 'Confirm Android shell command',
      target: serial,
      command: 'adb -s $serial shell $command',
      warning: 'Android shell commands are unrestricted and may modify system state, change device behavior, or remove data. Review the exact target and command before execution.',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB shell',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.shell', {
          'serial': serial,
          'command_text': command,
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.shell',
            'serial': serial,
            'command_text': command,
          },
        }),
      );
      if (mounted) {
        setState(() => _output = result.data['output'] as String? ?? 'Command completed.');
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reboot(String mode) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm device reboot'),
        content: Text('Send a reboot request to ' + serial + ' into ' + mode + ' mode?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    var rebootAccepted = false;
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB reboot (' + mode + ')',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.reboot', {
          'serial': serial,
          'mode': mode,
          'confirmed': true,
          'confirmation': {'operation': 'adb.reboot', 'serial': serial, 'mode': mode},
        }),
      );
      rebootAccepted = true;
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && rebootAccepted && (mode == 'bootloader' || mode == 'fastboot')) {
        final expectedFastbootMode = mode == 'fastboot' ? 'fastbootd' : 'bootloader';
        final transitioned = await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'fastboot',
          fastbootMode: expectedFastbootMode,
        );
        if (mounted && transitioned) {
          context.go('/fastboot');
        } else if (mounted) {
          setState(() => _output =
              'Reboot was accepted, but $serial was not detected in $expectedFastbootMode. Refresh devices and check the USB connection.');
        }
      } else if (mounted && rebootAccepted) {
        // Recovery and normal Android boot remain on the ADB workspace.
        await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: 'adb',
        );
      }
    }
  }

  Future<void> _closeLogcatCapture() async {
    final sink = _logcatCaptureSink;
    final path = _logcatCapturePath;
    _logcatCaptureSink = null;
    _logcatCapturePath = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Preserve the operation result even if the destination becomes unavailable.
    }
    if (mounted && path != null) {
      setState(() => _output = 'Full logcat stream saved to $path');
    }
  }

  Future<void> _captureLogcatToFile() async {
    final device = _selectedDevice();
    if (_logcatRequestId != null || _busy) return;
    if (device == null || device['transport'] != 'adb' || device['state'] != 'device') {
      setState(() => _output = 'Select an authorized online ADB device before capturing logcat.');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logcat.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Logcat text', extensions: ['txt', 'log']),
      ],
    );
    if (location == null || !mounted) return;
    try {
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
      sink.writeln('DroidLab logcat capture');
      sink.writeln('Device: ${_serial.text.trim()}');
      sink.writeln('Started: ${DateTime.now().toIso8601String()}');
      sink.writeln('Capture window: 1 hour maximum');
      sink.writeln();
      _logcatCaptureSink = sink;
      _logcatCapturePath = file.path;
      await _startLogcat(captureToFile: true);
    } catch (error) {
      await _closeLogcatCapture();
      if (mounted) {
        setState(() => _output = 'Could not start logcat file capture: $error');
      }
    }
  }

  Future<void> _startLogcat({bool captureToFile = false}) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _logcatRequestId != null) return;
    final filters = _logcatFilters.text.trim().isEmpty
        ? <String>[]
        : _logcatFilters.text.trim().split(RegExp(r'\s+'));
    try {
      final handle = await ref.read(backendClientProvider).startOperation(
        'adb.logcat.start',
        {
          'serial': serial,
          'filters': filters,
          if (captureToFile) 'timeout_seconds': 3600,
        },
      );
      if (!mounted) {
        await ref.read(backendClientProvider).cancel(handle.requestId);
        await _closeLogcatCapture();
        return;
      }
      final capturePathForRequest = captureToFile ? _logcatCapturePath : null;
      setState(() {
        _logcatRequestId = handle.requestId;
        _logLines.clear();
        _pausedLogSnapshot = [];
        _logPaused = false;
      });
      unawaited(trackOperation(
        ref,
        operation: captureToFile ? 'ADB logcat file capture (1 hour)' : 'ADB logcat',
        target: serial,
        action: () => handle.result,
        successSummary: (result) => result.data['duration_limit_reached'] == true
            ? 'One-hour logcat capture completed.'
            : 'Logcat stream stopped.',
      ).then((result) async {
        final manuallyStopped = _logcatManualStopRequestId == handle.requestId;
        if (manuallyStopped) _logcatManualStopRequestId = null;
        await _closeLogcatCapture();
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = manuallyStopped
                ? capturePathForRequest != null
                    ? 'Logcat capture stopped and saved to $capturePathForRequest'
                    : 'Logcat stream stopped.'
                : result.data['duration_limit_reached'] == true
                    ? 'One-hour logcat capture completed.'
                    : result.data.toString();
          });
        }
      }, onError: (Object error) async {
        final manuallyStopped = _logcatManualStopRequestId == handle.requestId;
        if (manuallyStopped) _logcatManualStopRequestId = null;
        await _closeLogcatCapture();
        if (mounted) {
          setState(() {
            _logcatRequestId = null;
            _output = manuallyStopped
                ? capturePathForRequest != null
                    ? 'Logcat capture stopped and saved to $capturePathForRequest'
                    : 'Logcat stream stopped.'
                : error.toString();
          });
        }
      }));
    } catch (error) {
      await _closeLogcatCapture();
      if (mounted) setState(() => _output = error.toString());
    }
  }

  Future<void> _stopLogcat() async {
    final id = _logcatRequestId;
    if (id == null) return;
    _logcatManualStopRequestId = id;
    final capturePath = _logcatCapturePath;
    try {
      await ref.read(backendClientProvider).cancel(id);
    } catch (error) {
      if (mounted) setState(() => _output = 'Could not stop logcat cleanly: $error');
    }
    await _closeLogcatCapture();
    if (mounted) {
      setState(() {
        _logcatRequestId = null;
        _output = capturePath != null
            ? 'Logcat capture stopped and saved to $capturePath'
            : 'Logcat stream stopped.';
      });
    }
  }

  Future<void> _browseSideloadPackage() async {
    const group = XTypeGroup(label: 'Recovery OTA ZIP', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null && mounted) setState(() => _package.text = file.path);
  }

  Future<void> _browseTransferLocal() async {
    if (_transferDirection == 'push') {
      final file = await openFile();
      if (file != null && mounted) setState(() => _transferLocal.text = file.path);
    } else {
      final directory = await getDirectoryPath(confirmButtonText: 'Use pull destination');
      if (directory != null && mounted) setState(() => _transferLocal.text = directory);
    }
  }

  void _dropTransferSource(DropDoneDetails detail) {
    if (_transferDirection == 'push' && detail.files.isNotEmpty) {
      setState(() => _transferLocal.text = detail.files.first.path);
    }
  }

  Future<void> _transferFile() async {
    final serial = _serial.text.trim();
    final localPath = _transferLocal.text.trim();
    final remotePath = _transferRemote.text.trim();
    if (_busy || serial.isEmpty || localPath.isEmpty || remotePath.isEmpty) return;
    if (_transferDirection == 'push' && !File(localPath).existsSync()) {
      setState(() => _output = 'Choose an existing local file to push.');
      return;
    }
    if (_transferDirection == 'pull' && !Directory(localPath).existsSync()) {
      setState(() => _output = 'Choose an existing local destination directory for pull.');
      return;
    }
    final sourcePath = _transferDirection == 'push' ? localPath : remotePath;
    final destinationPath = _transferDirection == 'push' ? remotePath : localPath;
    final intent = {
      'operation': 'adb.transfer',
      'serial': serial,
      'direction': _transferDirection,
      'source_path': sourcePath,
      'destination_path': destinationPath,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_transferDirection == 'push' ? 'Confirm file push' : 'Confirm file pull'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: ' + serial),
            Text('Direction: ' + _transferDirection.toUpperCase()),
            Text('Source: ' + sourcePath),
            Text('Destination: ' + destinationPath),
            const SizedBox(height: 10),
            const Text('Transfers use argument arrays, not a shell. Pull refuses to overwrite an existing local file. Review the paths before continuing.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transfer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB ' + _transferDirection,
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.transfer', {
          ...intent,
          'confirmed': true,
          'confirmation': intent,
        }, timeout: const Duration(hours: 1)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sideload() async {
    final serial = _serial.text.trim();
    final packagePath = _package.text.trim();    if (serial.isEmpty || packagePath.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm recovery sideload'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            Text('OTA package: ' + packagePath),
            const SizedBox(height: 12),
            const Text('Recovery sideload may update device partitions. A successful host exit does not prove Android accepted the update.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sideload')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB recovery sideload',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.sideload', {
          'serial': serial,
          'package_path': packagePath,
          'confirmed': true,
          'confirmation': {
            'operation': 'adb.sideload',
            'serial': serial,
            'package_path': packagePath,
          },
        }, timeout: const Duration(minutes: 35)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBugreport() async {
    final serial = _serial.text.trim();
    final outputPath = _bugreport.text.trim();
    if (serial.isEmpty || outputPath.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate device bugreport?'),
        content: Text(
          'The bugreport for ' + serial +
          ' can contain account, network, location and application diagnostics. Save it only to a location you control and review it before sharing.\n\nOutput: ' +
          outputPath,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate report')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'ADB bugreport',
        target: serial,
        action: () => ref.read(backendClientProvider).request('adb.bugreport', {
          'serial': serial,
          'output_path': outputPath,
        }, timeout: const Duration(minutes: 20)),
        successSummary: (result) => 'Report saved to ' + (result.data['path']?.toString() ?? outputPath),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDeviceInfo() async {
    final serial = _serial.text.trim();
    final target = _selectedDevice();
    if (serial.isEmpty || target == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'device.info',
        {'serial': serial},
      );
      if (mounted) {
        final metadata = result.data['metadata'] as Map<String, dynamic>? ?? const {};
        setState(() {
          _output = metadata.entries
              .map((entry) => entry.key + ': ' +
                  (entry.value?.toString().isNotEmpty == true
                      ? entry.value.toString()
                      : '—'))
              .join('\\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browseLogSavePath() async {
    const group = XTypeGroup(label: 'Logcat text', extensions: ['txt', 'log']);
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logcat.txt',
      acceptedTypeGroups: [group],
    );
    if (location != null && mounted) {
      setState(() => _logSavePath.text = location.path);
    }
  }

  Future<void> _browseBugreportOutput() async {
    const group = XTypeGroup(label: 'Bugreport ZIP', extensions: ['zip']);
    final location = await getSaveLocation(
      suggestedName: 'bugreport.zip',
      acceptedTypeGroups: [group],
    );
    if (location != null && mounted) {
      setState(() => _bugreport.text = location.path);
    }
  }

  Future<void> _saveLogcat() async {
    final path = _logSavePath.text.trim();
    if (path.isEmpty || _logLines.isEmpty) return;
    try {
      final file = File(path).absolute;
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      await file.writeAsString(_logLines.join('\n'), mode: FileMode.writeOnly);
      if (mounted) {
        setState(() => _output = 'Saved ' + _logLines.length.toString() + ' logcat lines to ' + file.path);
      }
    } catch (error) {
      if (mounted) setState(() => _output = 'Could not save logcat: ' + error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceListProvider);
    final globalTarget = ref.watch(selectedTargetSerialProvider);
    if (globalTarget != null && _serial.text != globalTarget) _serial.text = globalTarget;
    final discoveredDevices = (devicesAsync.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final selectedDevices = discoveredDevices
        .where((device) => device['serial'] == _serial.text.trim())
        .toList();
    final selectedDevice = selectedDevices.isEmpty ? null : selectedDevices.first;
    final selectedTransport = selectedDevice?['transport'] as String?;
    final Object? selectedState =
        selectedDevice == null ? null : selectedDevice['state'];
    final String? selectedAdbState = selectedTransport == 'adb'
        ? selectedState as String?
        : null;
    final selectedFastboot = selectedTransport == 'fastboot' &&
        selectedDevice?['state'] == 'fastboot';
    final canRunAdbCommands = selectedAdbState == 'device';
    final canReboot = canRunAdbCommands ||
        selectedAdbState == 'recovery' || selectedFastboot;
    final selectedSerial = selectedDevices.isEmpty ? null : _serial.text.trim();
    final targetSelector = SizedBox(
      width: 390,
      child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: selectedSerial,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Target Serial'),
          hint: const Text('Select an authorized ADB target'),
          items: discoveredDevices.map((device) {
            final serial = device['serial'] as String;
            final transport = device['transport'] as String? ?? 'unknown';
            final model = device['model'] as String? ?? '';
            return DropdownMenuItem(value: serial,
              child: Text('$serial (${model} · $transport)',
                overflow: TextOverflow.ellipsis));
          }).toList(),
          onChanged: _busy ? null : (value) {
            setState(() => _serial.text = value ?? '');
            ref.read(selectedTargetSerialProvider.notifier).state = value;
          },
        )),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Refresh devices',
          onPressed: _busy ? null : _refreshDevices,
          icon: const Icon(Icons.refresh),
        ),
      ]),
    );
    Widget panel(String title, String subtitle, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          ...children,
        ]),
      ),
    );
    final shellPanel = panel(
      'Guarded ADB Shell (adb.shell)',
      'Dispatches discrete argument arrays without host shell interpolation.',
      [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final preset in const [
            ('Build Fingerprint', 'getprop ro.build.fingerprint'),
            ('Active Boot Slot', 'getprop ro.boot.slot_suffix'),
            ('Battery Dump', 'dumpsys battery'),
            ('SELinux Status', 'getenforce'),
            ('Mounted Partitions', 'cat /proc/mounts'),
          ])
            OutlinedButton(
              onPressed: _busy ? null : () {
                _command.text = preset.$2;
                _command.selection = TextSelection.collapsed(offset: _command.text.length);
              },
              child: Text(preset.$1),
            ),
        ]),
        const SizedBox(height: 12),
        DropTarget(
          onDragDone: _dropCommandPath,
          child: _TextField(controller: _command, label: 'Shell command arguments',
            hint: 'getprop ro.build.version.release'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy || !canRunAdbCommands ? null : _runShell,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Guarded Shell'),
          ),
          OutlinedButton(
            onPressed: _busy || !(canRunAdbCommands || selectedFastboot) ? null : _loadDeviceInfo,
            child: const Text('Device info'),
          ),
        ]),
        if (!canRunAdbCommands && !selectedFastboot)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              selectedDevice == null
                ? 'Select an authorized ADB device before running shell commands.'
                : 'Selected target is ${selectedTransport ?? 'unknown'} / ${selectedState ?? 'unknown'}. ADB shell requires an authorized device transport.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    final rebootPanel = panel(
      'Mode-Aware Reboot Routing (adb.reboot)',
      'Routes through the active transport and waits for the device to reappear.',
      [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('system'), child: const Text('Reboot to system')),
          OutlinedButton(onPressed: _busy || !canReboot ? null : () => _reboot('recovery'), child: const Text('Reboot to recovery')),
          OutlinedButton(onPressed: _busy || !canRunAdbCommands ? null : () => _reboot('bootloader'), child: const Text('Reboot to bootloader')),
          OutlinedButton(onPressed: _busy || !canRunAdbCommands ? null : () => _reboot('fastboot'), child: const Text('Reboot to Fastbootd')),
        ]),
      ],
    );
    final transferPanel = panel(
      'Atomic Single-File Push & Pull',
      'Rejects symlinked local sources and refuses to overwrite existing pull destinations.',
      [
        DropdownButtonFormField<String>(
          initialValue: _transferDirection,
          decoration: const InputDecoration(labelText: 'Transfer direction'),
          items: const [
            DropdownMenuItem(value: 'push', child: Text('Computer → device (push)')),
            DropdownMenuItem(value: 'pull', child: Text('Device → computer (pull)')),
          ],
          onChanged: _busy ? null : (value) {
            if (value == null) return;
            setState(() {
              _transferDirection = value;
              _transferLocal.clear();
              _transferRemote.text = value == 'push' ? '/sdcard/Download/' : '/sdcard/Download/file';
            });
          },
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropTarget(
            onDragDone: _dropTransferSource,
            child: _TextField(controller: _transferLocal,
              label: _transferDirection == 'push' ? 'Local source path' : 'Local destination path'),
          )),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _busy ? null : _browseTransferLocal, child: const Text('Browse…')),
        ]),
        const SizedBox(height: 10),
        _TextField(controller: _transferRemote,
          label: _transferDirection == 'push' ? 'Android destination path' : 'Android source path'),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: FilledButton(
          onPressed: _busy || !canRunAdbCommands ? null : _transferFile,
          child: Text(_transferDirection == 'push' ? 'Push' : 'Pull'),
        )),
      ],
    );
    final sideloadPanel = panel(
      'Recovery OTA Sideload (adb.sideload)',
      'Requires a target in sideload or recovery state.',
      [
        Row(children: [
          Expanded(child: DropTarget(
            onDragDone: (detail) {
              if (detail.files.isNotEmpty) setState(() => _package.text = detail.files.first.path);
            },
            child: _TextField(controller: _package, label: 'OTA ZIP package path'),
          )),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseSideloadPackage, child: const Text('Browse ZIP…')),
        ]),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: FilledButton(
          onPressed: _busy || !(selectedAdbState == 'device' || selectedAdbState == 'recovery' || selectedAdbState == 'sideload') ? null : _sideload,
          child: const Text('Sideload ZIP'),
        )),
      ],
    );
    final diagnosticsPanel = panel(
      'Logcat & Bugreport',
      'Capture diagnostics locally. Review sensitive output before sharing.',
      [
        _TextField(controller: _logcatFilters, label: 'Logcat filters (optional)', hint: '*:W or ActivityManager:I'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _TextField(controller: _logSavePath, label: 'Logcat save path')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseLogSavePath, child: const Text('Browse…')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: _logcatRequestId != null ? _stopLogcat : (canRunAdbCommands ? _startLogcat : null),
            child: Text(_logcatRequestId == null ? 'Start logcat' : 'Stop logcat'),
          ),
          OutlinedButton(onPressed: _saveLogcat, child: const Text('Save captured buffer')),
          OutlinedButton(
            onPressed: _logcatRequestId == null && !_busy && canRunAdbCommands ? _captureLogcatToFile : null,
            child: const Text('Capture logcat to file (1 hour)'),
          ),
        ]),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: _TextField(controller: _bugreport, label: 'Bugreport output ZIP path')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseBugreportOutput, child: const Text('Browse…')),
        ]),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: OutlinedButton(
          onPressed: _busy || !canRunAdbCommands ? null : _createBugreport,
          child: const Text('Generate bugreport'),
        )),
      ],
    );
    return _PageFrame(
      title: 'ADB Toolkit & Guarded Transfers',
      subtitle: 'Every shell command, reboot, push/pull, and sideload requires target-and-argument confirmation',
      actions: [targetSelector],
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          shellPanel,
          const SizedBox(height: 14),
          rebootPanel,
        ]);
        final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          transferPanel,
          const SizedBox(height: 14),
          sideloadPanel,
          const SizedBox(height: 14),
          diagnosticsPanel,
        ]);
        return Column(children: [
          if (devicesAsync.hasError)
            Padding(padding: const EdgeInsets.only(bottom: 10),
              child: Text('Device scan failed: ${devicesAsync.error}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_busy) const LinearProgressIndicator(),
          Expanded(child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: SingleChildScrollView(child: left)),
                const SizedBox(width: 24),
                Expanded(child: SingleChildScrollView(child: right)),
              ])
            : ListView(children: [shellPanel, const SizedBox(height: 14), rebootPanel,
                const SizedBox(height: 14), transferPanel, const SizedBox(height: 14),
                sideloadPanel, const SizedBox(height: 14), diagnosticsPanel])),
          if (_output.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OutputPanel(output: _output),
          ],
          if (_logcatRequestId != null || _logLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text('LIVE LOGCAT', style: Theme.of(context).textTheme.titleSmall)),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      if (!_logPaused) {
                        _pausedLogSnapshot = List<String>.of(_logLines);
                        _logPaused = true;
                      } else {
                        _logPaused = false;
                        _pausedLogSnapshot = [];
                      }
                    }),
                    child: Text(_logPaused ? 'Resume display' : 'Pause display'),
                  ),
                ]),
                const SizedBox(height: 8),
                _TextField(controller: _logDisplayFilter, label: 'Filter visible log lines',
                  hint: 'Case-insensitive text filter', onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                _OutputPanel(output: (() {
                  final source = _logPaused ? _pausedLogSnapshot : _logLines;
                  final needle = _logDisplayFilter.text.trim().toLowerCase();
                  return source.where((line) => needle.isEmpty || line.toLowerCase().contains(needle)).join('\n');
                })()),
                if (_logPaused) Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Display paused. Incoming lines continue to be buffered.',
                    style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ))),
          ],
        ]);
      }),
    );
  }
}
