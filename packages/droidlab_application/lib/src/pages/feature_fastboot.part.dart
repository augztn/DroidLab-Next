part of 'feature_pages.dart';

class FastbootToolkitPage extends ConsumerStatefulWidget {
  const FastbootToolkitPage({super.key});

  @override
  ConsumerState<FastbootToolkitPage> createState() => _FastbootToolkitPageState();
}

class _FastbootToolkitPageState extends ConsumerState<FastbootToolkitPage> {
  final _serial = TextEditingController();
  final _partition = TextEditingController();
  final _image = TextEditingController();
  final _advancedCommand = TextEditingController(text: 'getvar all');
  String? _selectedSerial;
  String _advancedPreview = '';
  String _output = '';
  bool _busy = false;
  List<Map<String, dynamic>> _discoveredPartitions = [];

  @override
  void dispose() {
    _serial.dispose();
    _partition.dispose();
    _image.dispose();
    _advancedCommand.dispose();
    super.dispose();
  }

  Future<void> _browseFastbootImage() async {
    const group = XTypeGroup(label: 'Android partition image', extensions: ['img']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    final name = file.name.toLowerCase();
    const partitions = {
      'boot.img': 'boot',
      'vendor.img': 'vendor',
      'vendor_boot.img': 'vendor_boot',
      'init_boot.img': 'init_boot',
      'dtbo.img': 'dtbo',
      'vbmeta.img': 'vbmeta',
      'recovery.img': 'recovery',
      'system.img': 'system',
      'product.img': 'product',
      'odm.img': 'odm',
      'system_ext.img': 'system_ext',
      'vbmeta_system.img': 'vbmeta_system',
      'vbmeta_vendor.img': 'vbmeta_vendor',
    };
    setState(() {
      _image.text = file.path;
      _partition.text = partitions[name] ?? _partition.text;
    });
  }

  void _acceptImageDrop(DropDoneDetails detail) {
    if (detail.files.isEmpty) return;
    final file = detail.files.first;
    setState(() {
      _image.text = file.path;
      if (_partition.text.trim().isEmpty) {
        final name = file.name;
        _partition.text = name.toLowerCase().endsWith('.img')
            ? name.substring(0, name.length - 4)
            : name;
      }
    });
  }

  Future<void> _mutate(String operation) async {
    final serial = _serial.text.trim();
    final partition = _partition.text.trim();
    final image = _image.text.trim();
    if (serial.isEmpty || partition.isEmpty ||
        (operation == 'fastboot.flash' && image.isEmpty) || _busy) return;

    final command = operation == 'fastboot.flash'
        ? 'fastboot -s ' + serial + ' flash ' + partition + ' ' + image
        : 'fastboot -s ' + serial + ' erase ' + partition;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(operation == 'fastboot.flash' ? 'Confirm partition flash' : 'Confirm partition erase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + serial),
            Text('Partition: ' + partition),
            if (operation == 'fastboot.flash') Text('Image: ' + image),
            const SizedBox(height: 12),
            const Text('This operation modifies device partitions and may make the device unbootable.'),
            const SizedBox(height: 12),
            SelectableText(command, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I understand — execute')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final args = <String, dynamic>{
        'serial': serial,
        'partition': partition,
        'confirmed': true,
        'confirmation': operation == 'fastboot.flash'
            ? {
                'operation': 'fastboot.flash',
                'serial': serial,
                'partition': partition,
                'image_path': image,
              }
            : {
                'operation': 'fastboot.erase',
                'serial': serial,
                'partition': partition,
              },
      };
      if (operation == 'fastboot.flash') args['image_path'] = image;
      final result = await trackOperation(
        ref,
        operation: operation == 'fastboot.flash'
            ? 'Fastboot flash ' + partition
            : 'Fastboot erase ' + partition,
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          operation,
          args,
          timeout: const Duration(minutes: 20),
        ),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebootFastboot(String mode) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final label = mode == 'system' ? 'Android' : mode == 'fastbootd' ? 'Fastbootd (userspace Fastboot)' : mode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Fastboot reboot'),
        content: Text('Reboot Fastboot target ' + serial + ' to ' + label + '?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Fastboot reboot (' + mode + ')',
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          'fastboot.reboot',
          {
            'serial': serial,
            'mode': mode,
            'confirmed': true,
            'confirmation': {'operation': 'fastboot.reboot', 'serial': serial, 'mode': mode},
          },
        ),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) {
        final expectedTransport = mode == 'system' || mode == 'recovery'
            ? 'adb'
            : 'fastboot';
        final expectedFastbootMode = mode == 'fastbootd'
            ? 'fastbootd'
            : mode == 'bootloader'
                ? 'bootloader'
                : null;
        final transitioned = await _waitForDeviceTransport(
          ref: ref,
          serial: serial,
          transport: expectedTransport,
          fastbootMode: expectedFastbootMode,
        );
        if (!mounted) return;
        if (transitioned && expectedTransport == 'adb') {
          context.go('/adb');
        } else if (!transitioned) {
          final expectedLabel = expectedFastbootMode ??
              (mode == 'recovery' ? 'recovery / ADB' : expectedTransport);
          setState(() => _output =
              'Reboot was accepted, but $serial was not detected in $expectedLabel. Refresh devices and check the USB connection.');
        }
      }
    }
  }

  bool _isFastbootDiscoveryCommand(String command) {
    final verb = command.trim().split(RegExp(r'\s+')).first.toLowerCase();
    return const {'devices', 'help', '--help', '--version', 'version'}.contains(verb);
  }

  String _fastbootCommandPreview(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    if (_isFastbootDiscoveryCommand(trimmed) || _serial.text.trim().isEmpty) {
      return 'fastboot ' + trimmed;
    }
    return 'fastboot -s ' + _serial.text.trim() + ' ' + trimmed;
  }

  Future<void> _runAdvancedCommand() async {
    final serial = _serial.text.trim();
    final command = _advancedCommand.text.trim();
    if (command.isEmpty || _busy) return;
    final discovery = _isFastbootDiscoveryCommand(command);
    if (!discovery && serial.isEmpty) {
      setState(() => _output = 'Select a Fastboot device for device-targeted commands. Discovery/help/version commands do not require a target.');
      return;
    }
    final target = discovery ? null : serial;
    final preview = _fastbootCommandPreview(command);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm advanced Fastboot command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ' + (target ?? 'host / discovery command')),
            const SizedBox(height: 8),
            Text(discovery
                ? 'This is a host-side Fastboot discovery/help command and does not mutate a selected device.'
                : 'Advanced commands are unrestricted and may erase data, change boot state, or make the device unbootable. Review the exact command.'),
            const SizedBox(height: 12),
            SelectableText(preview, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: discovery
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Execute command'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Advanced Fastboot: ' + command,
        target: target ?? 'host',
        action: () => ref.read(backendClientProvider).request('fastboot.command', {
          'serial': target,
          'command': command,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.command',
            'serial': target,
            'command': command,
          },
        }, timeout: const Duration(minutes: 30)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discoverPartitions() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Discover Fastboot partitions',
        target: serial,
        action: () => ref.read(backendClientProvider).request(
          'fastboot.partitions',
          {'serial': serial},
        ),
      );
      final partitions = (result.data['partitions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (mounted) {
        setState(() {
          _discoveredPartitions = partitions;
          _output = partitions.map((item) {
            final details = [
              if (item['size'] != null) 'size: ${item['size']}',
              if (item['type'] != null) 'type: ${item['type']}',
              if (item['has_slot'] != null) 'slot: ${item['has_slot']}',
              if (item['is_logical'] != null) 'logical: ${item['is_logical']}',
            ].join(', ');
            return '${item['name']}${details.isEmpty ? '' : ' — $details'}';
          }).join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readFastbootInfo(String serial) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(backendClientProvider).request(
        'device.info',
        {'serial': serial},
      );
      if (mounted) {
        final metadata = result.data['metadata'] as Map<String, dynamic>;
        setState(() {
          _output = metadata.entries
              .map((entry) => entry.key + ': ' +
                  (entry.value?.toString().isNotEmpty == true
                      ? entry.value.toString()
                      : '—'))
              .join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActiveSlot(String slot) async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy || !const {'a', 'b', 'other'}.contains(slot)) return;
    final command = 'fastboot -s $serial --set-active=$slot';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(slot == 'other' ? 'Switch to the other active slot?' : 'Set active slot ${slot.toUpperCase()}?'),
        content: Text(
          slot == 'other'
              ? 'Ask the bootloader to select the slot opposite the currently active slot on $serial. The bootloader resolves "other"; verify the resulting current-slot before rebooting. This can make the device fail to start if that slot is incomplete.\n\nfastboot -s $serial set_active other'
              : 'Change the active boot slot on $serial. This affects the next boot and can make the device fail to start if the selected slot is incomplete.\n\n$command',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change active slot'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: slot == 'other' ? 'Fastboot switch to other active slot' : 'Fastboot set active slot ${slot.toUpperCase()}',
        target: serial,
        action: () => ref.read(backendClientProvider).request('fastboot.set_active', {
          'serial': serial,
          'slot': slot,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.set_active',
            'serial': serial,
            'slot': slot,
          },
        }),
      );
      if (mounted) setState(() => _output = result.data.toString());
      ref.invalidate(deviceListProvider);
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipeUserdata() async {
    final serial = _serial.text.trim();
    if (serial.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm factory data wipe'),
        content: Text(
          'fastboot -w will erase userdata and cache on ' + serial +
          '. This permanently removes local data. Confirm only after verifying your backup and target.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase all user data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await trackOperation(
        ref,
        operation: 'Fastboot wipe userdata and cache',
        target: serial,
        action: () => ref.read(backendClientProvider).request('fastboot.wipe', {
          'serial': serial,
          'confirmed': true,
          'confirmation': {
            'operation': 'fastboot.wipe',
            'serial': serial,
            'mode': 'wipe-userdata',
          },
        }, timeout: const Duration(minutes: 12)),
      );
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceListProvider);
    final devices = (devicesAsync.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((device) => device['transport'] == 'fastboot')
        .toList();
    final serials = devices.map((device) => device['serial'] as String).toList();
    final selectedSerial = serials.contains(_selectedSerial) ? _selectedSerial : null;
    if (selectedSerial != null && selectedSerial != _serial.text && !_busy) {
      _serial.text = selectedSerial;
    }
    return _PageFrame(
    title: 'Fastboot Toolkit',
    subtitle: 'Destructive actions require fresh target validation and an explicit confirmation.',
    child: ListView(children: [
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: selectedSerial,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Detected Fastboot devices',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select a Fastboot device'),
          items: devices.map((device) => DropdownMenuItem<String>(
            value: device['serial'] as String,
            child: Text(
              '${device['serial']} · ${device['mode'] == 'fastbootd' ? 'Fastbootd' : device['mode'] == 'bootloader' ? 'Bootloader Fastboot' : 'Fastboot mode unknown'}',
              overflow: TextOverflow.ellipsis,
            ),
          )).toList(),
          onChanged: (value) => setState(() {
            _selectedSerial = value;
            _serial.text = value ?? '';
          }),
        )),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Refresh devices',
          onPressed: _busy ? null : () => ref.invalidate(deviceListProvider),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      if (devicesAsync.hasError) Text('Device scan failed: ${devicesAsync.error}'),
      if (devices.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No Fastboot device detected. Use ADB Toolkit → Fastbootd to enter userspace Fastboot, or reboot to bootloader, then refresh.'),
        ),
      const SizedBox(height: 12),
      if (_discoveredPartitions.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: _discoveredPartitions.any((item) => item['name'] == _partition.text)
              ? _partition.text
              : null,
          decoration: const InputDecoration(
            labelText: 'Discovered partitions',
            border: OutlineInputBorder(),
          ),
          items: _discoveredPartitions.map((item) {
            final name = item['name'] as String;
            final size = item['size']?.toString();
            return DropdownMenuItem<String>(
              value: name,
              child: Text(size == null ? name : '$name · $size'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _partition.text = value);
          },
        ),
      _TextField(controller: _partition, label: 'Partition name', hint: 'boot_a'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropTarget(
          onDragDone: _acceptImageDrop,
          child: _TextField(controller: _image, label: 'Image path', hint: 'Drop a partition .img or enter its path'),
        )),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _browseFastbootImage, child: const Text('Browse image…')),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _busy || selectedSerial == null ? null : _discoverPartitions,
          icon: const Icon(Icons.list_alt),
          label: const Text('Discover partitions'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || selectedSerial == null ? null : () => _readFastbootInfo(selectedSerial),
          icon: const Icon(Icons.info_outline),
          label: const Text('Device info'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _mutate('fastboot.flash'),
          icon: const Icon(Icons.flash_on),
          label: const Text('Flash image'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _mutate('fastboot.erase'),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Erase selected partition'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('system'),
          child: const Text('Reboot system'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('recovery'),
          child: const Text('Reboot recovery'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _rebootFastboot('bootloader'),
          child: const Text('Reboot bootloader'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : () => _rebootFastboot('fastbootd'),
          child: const Text('Reboot to Fastbootd'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('ERASE & FORMAT', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: _busy ? null : () {
            _partition.text = 'cache';
            _mutate('fastboot.erase');
          },
          child: const Text('Erase cache'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () {
            _partition.text = 'userdata';
            _mutate('fastboot.erase');
          },
          child: const Text('Erase userdata'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : _wipeUserdata,
          child: const Text('Wipe data (fastboot -w)'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('BOOT SLOT', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton(
          onPressed: _busy ? null : () => _setActiveSlot('a'),
          child: const Text('Set active slot A'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _setActiveSlot('b'),
          child: const Text('Set active slot B'),
        ),
        FilledButton.tonal(
          onPressed: _busy || selectedSerial == null ? null : () => _setActiveSlot('other'),
          child: const Text('Switch to other slot'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('ADVANCED FASTBOOT COMMAND', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _TextField(
        controller: _advancedCommand,
        label: 'Fastboot arguments',
        hint: 'getvar all · flashing get_unlock_ability',
        onChanged: (value) => setState(() {
          _advancedPreview = _fastbootCommandPreview(value);
        }),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: () => setState(() {
            _advancedPreview = _fastbootCommandPreview(_advancedCommand.text);
          }),
          child: const Text('Preview command'),
        ),
        FilledButton(
          onPressed: _busy ? null : _runAdvancedCommand,
          child: const Text('Run command'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _advancedCommand.clear();
            _advancedPreview = '';
          }),
          child: const Text('Clear command'),
        ),
      ]),
      if (_advancedPreview.isNotEmpty)
        SelectableText(_advancedPreview, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      const SizedBox(height: 18),
      if (_busy) const LinearProgressIndicator(),
      _OutputPanel(output: _output.isEmpty ? 'Fastboot operation results appear here.' : _output),
    ]),
  );
  }
}

