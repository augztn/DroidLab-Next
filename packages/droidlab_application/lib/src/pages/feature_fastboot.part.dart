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
    var rebootAccepted = false;
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
      rebootAccepted = true;
      if (mounted) setState(() => _output = result.data.toString());
    } catch (error) {
      if (mounted) setState(() => _output = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && rebootAccepted) {
        final expectedTransport = mode == 'system' || mode == 'recovery'
            ? 'adb'
            : 'fastboot';
        final expectedFastbootMode = mode == 'fastbootd'
            ? 'fastbootd'
            : mode == 'bootloader'
                ? 'bootloader'
                : null;
        final transitioned = await _waitForDeviceTransport(
          context: context,
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

  FastbootCommand? _parseFastbootCommand(String command) =>
      FastbootCommand.parse(command);

  bool _isFastbootDiscoveryCommand(String command) =>
      _parseFastbootCommand(command)?.isDiscovery ?? false;

  String _fastbootCommandPreview(String command) {
    final parsed = _parseFastbootCommand(command);
    if (parsed == null || parsed.arguments.isEmpty) return '';
    final arguments = parsed.preview;
    if (parsed.isDiscovery ||
        _serial.text.trim().isEmpty ||
        parsed.hasExplicitSerial) {
      return 'fastboot ' + arguments;
    }
    return 'fastboot -s ' + _serial.text.trim() + ' ' + arguments;
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
      if (mounted) {
        setState(() => _output = result.data.toString());
        ref.invalidate(deviceListProvider);
      }
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
    final globalTarget = ref.watch(selectedTargetSerialProvider);
    final allDevices = (devicesAsync.valueOrNull?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>().toList();
    final fastbootDevices = allDevices.where((device) => device['transport'] == 'fastboot').toList();
    final serials = fastbootDevices.map((device) => device['serial'] as String).toList();
    final currentSelection = globalTarget ?? _selectedSerial ?? _serial.text.trim();
    final selectedSerial = serials.contains(currentSelection)
        ? currentSelection
        : fastbootDevices.length == 1
            ? fastbootDevices.single['serial'] as String
            : null;
    if (selectedSerial != null && selectedSerial != globalTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedTargetSerialProvider) == globalTarget) {
          ref.read(selectedTargetSerialProvider.notifier).state = selectedSerial;
        }
      });
    }
    if (selectedSerial != null && selectedSerial != _serial.text && !_busy) {
      _serial.text = selectedSerial;
    }
    final matchingDevices = fastbootDevices.where((device) => device['serial'] == selectedSerial).toList();
    final selectedDevice = matchingDevices.isEmpty ? null : matchingDevices.first;
    final fastbootTarget = isFastbootDeviceReady(selectedDevice);
    final targetSelector = SizedBox(
      width: 390,
      child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: selectedSerial,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Target Serial'),
          hint: const Text('Select a device'),
          items: fastbootDevices.map((device) {
            final serial = device['serial'] as String;
            final model = device['model']?.toString() ?? device['product']?.toString() ?? 'Android';
            final transport = device['transport']?.toString() ?? 'unknown';
            final mode = device['mode']?.toString() ?? transport;
            return DropdownMenuItem(value: serial,
              child: Text('$serial ($model · $mode)', overflow: TextOverflow.ellipsis));
          }).toList(),
          onChanged: _busy ? null : (value) {
            setState(() {
              _selectedSerial = value;
              _serial.text = value ?? '';
            });
            ref.read(selectedTargetSerialProvider.notifier).state = value;
          },
        )),
        const SizedBox(width: 6),
        IconButton(tooltip: 'Refresh devices', onPressed: _busy ? null : () => ref.invalidate(deviceListProvider),
          icon: const Icon(Icons.refresh)),
      ]),
    );
    Widget panel(String title, String subtitle, List<Widget> children) {
      final icon = switch (title) {
        'Guarded Partition Flash (fastboot.flash)' => Icons.system_update_alt_rounded,
        'A/B Active Slot Switcher (fastboot.set_active)' => Icons.swap_horiz_rounded,
        'Guarded Erase & Factory Wipe' => Icons.delete_sweep_outlined,
        'Mode-Aware Fastboot Reboot' => Icons.restart_alt_rounded,
        _ => Icons.terminal_rounded,
      };
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(21),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
              ])),
            ]),
            const SizedBox(height: 19),
            ...children,
          ]),
        ),
      );
    }
    final flashPanel = panel(
      'Guarded Partition Flash (fastboot.flash)',
      'Validates the partition allowlist, unlocked bootloader state, and fresh transport scan before dispatch.',
      [
        if (_discoveredPartitions.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _discoveredPartitions.any((item) => item['name'] == _partition.text) ? _partition.text : null,
            decoration: const InputDecoration(labelText: 'Discovered partitions'),
            items: _discoveredPartitions.map((item) {
              final name = item['name'] as String;
              final size = item['size']?.toString();
              return DropdownMenuItem(value: name, child: Text(size == null ? name : '$name · $size'));
            }).toList(),
            onChanged: (value) { if (value != null) setState(() => _partition.text = value); },
          ),
        _TextField(controller: _partition, label: 'Target partition (ASCII allowlist + _a / _b suffix)', hint: 'boot'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropTarget(
            onDragDone: _acceptImageDrop,
            child: _TextField(controller: _image, label: 'Verified image path (.img)', hint: 'Drop a partition image or enter its path'),
          )),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _browseFastbootImage, child: const Text('Browse image…')),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || !fastbootTarget ? null : () => _mutate('fastboot.flash'),
          child: const Text('Preview & Confirm Flash'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _busy || !fastbootTarget ? null : _discoverPartitions,
            icon: const Icon(Icons.list_alt), label: const Text('Discover partitions')),
          OutlinedButton.icon(
            onPressed: _busy || !fastbootTarget ? null : () => _readFastbootInfo(selectedSerial!),
            icon: const Icon(Icons.info_outline), label: const Text('Device info')),
        ]),
      ],
    );
    final slotPanel = panel(
      'A/B Active Slot Switcher (fastboot.set_active)',
      'Uses primary --set-active syntax with automatic legacy set_active fallback.',
      [
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: _busy || !fastbootTarget ? null : () => _setActiveSlot('a'),
            child: const Text('Set Active Slot A'),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(
            onPressed: _busy || !fastbootTarget ? null : () => _setActiveSlot('b'),
            child: const Text('Set Active Slot B'),
          )),
        ]),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy || !fastbootTarget ? null : () => _setActiveSlot('other'),
          child: const Text('Switch to other slot'),
        ),
      ],
    );
    final erasePanel = panel(
      'Guarded Erase & Factory Wipe',
      'Destructive partition erase requires exact partition confirmation.',
      [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: _busy || !fastbootTarget ? null : () => _mutate('fastboot.erase'),
            child: const Text('Erase selected partition'),
          ),
          OutlinedButton(
            onPressed: _busy || !fastbootTarget ? null : () { _partition.text = 'cache'; _mutate('fastboot.erase'); },
            child: const Text('Erase cache'),
          ),
          OutlinedButton(
            onPressed: _busy || !fastbootTarget ? null : () { _partition.text = 'userdata'; _mutate('fastboot.erase'); },
            child: const Text('Erase userdata'),
          ),
          FilledButton.tonal(
            onPressed: _busy || !fastbootTarget ? null : _wipeUserdata,
            child: const Text('Factory wipe'),
          ),
        ]),
      ],
    );
    final rebootPanel = panel(
      'Mode-Aware Fastboot Reboot',
      'Select the next device transport. Reboot operations require a fresh target check.',
      [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy || !fastbootTarget ? null : () => _rebootFastboot('system'), child: const Text('Reboot system')),
          OutlinedButton(onPressed: _busy || !fastbootTarget ? null : () => _rebootFastboot('recovery'), child: const Text('Reboot recovery')),
          OutlinedButton(onPressed: _busy || !fastbootTarget ? null : () => _rebootFastboot('bootloader'), child: const Text('Reboot bootloader')),
          FilledButton.tonal(onPressed: _busy || !fastbootTarget ? null : () => _rebootFastboot('fastbootd'), child: const Text('Reboot to Fastbootd')),
        ]),
      ],
    );
    final advancedPanel = panel(
      'Advanced Fastboot Command',
      'Preview the exact argument vector before execution.',
      [
        _TextField(controller: _advancedCommand, label: 'Fastboot arguments',
          hint: 'getvar all · flashing get_unlock_ability',
          onChanged: (value) => setState(() => _advancedPreview = _fastbootCommandPreview(value))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: () => setState(() => _advancedPreview = _fastbootCommandPreview(_advancedCommand.text)),
            child: const Text('Preview command')),
          FilledButton(onPressed: _busy || !fastbootTarget ? null : _runAdvancedCommand,
            child: const Text('Run command')),
          TextButton(onPressed: () => setState(() { _advancedCommand.clear(); _advancedPreview = ''; }),
            child: const Text('Clear')),
        ]),
        if (_advancedPreview.isNotEmpty)
          SelectableText(_advancedPreview, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ],
    );
    return _PageFrame(
      title: 'Fastboot Toolkit & Guarded Flashing',
      subtitle: 'Strict ASCII partition allowlist · Distinguishes bootloader Fastboot vs Userspace Fastbootd',
      actions: [targetSelector],
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final warning = selectedDevice != null && !fastbootTarget
          ? Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Theme.of(context).colorScheme.tertiary),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.tertiary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Selected target ${selectedDevice['serial']} is currently in ${selectedDevice['transport']} mode. Fastboot mutations require bootloader Fastboot or Fastbootd transport.',
                    style: Theme.of(context).textTheme.bodySmall)),
                  TextButton(onPressed: () => context.go('/adb'), child: const Text('Open ADB Toolkit')),
                ]),
              ),
            )
          : null;
        final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          flashPanel,
          const SizedBox(height: 14),
          rebootPanel,
        ]);
        final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          slotPanel,
          const SizedBox(height: 14),
          erasePanel,
          const SizedBox(height: 14),
          advancedPanel,
        ]);
        final deviceLabel = selectedDevice == null
            ? 'No target selected'
            : (selectedDevice['model']?.toString().trim().isNotEmpty == true
                ? selectedDevice['model'].toString()
                : selectedDevice['product']?.toString() ?? 'Android device');
        final transportLabel = selectedDevice == null
            ? 'Waiting for a device'
            : '${selectedDevice['transport'] ?? 'unknown'} · ${selectedDevice['mode'] ?? selectedDevice['state'] ?? 'unknown'}';
        final targetStatus = Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (fastbootTarget
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant).withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  fastbootTarget ? Icons.usb_rounded : Icons.usb_off_rounded,
                  color: fastbootTarget
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(deviceLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(selectedSerial == null ? 'Connect a device or select one above' : '$selectedSerial  ·  $transportLabel',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: selectedSerial == null ? null : 'monospace')),
              ])),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: (fastbootTarget
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.surfaceContainerHighest).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Text(
                  fastbootTarget ? 'FASTBOOT READY' : selectedDevice == null ? 'NOT CONNECTED' : 'WRONG MODE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fastbootTarget
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.45),
                ),
              ),
            ]),
          ),
        );
        return Column(children: [
          targetStatus,
          const SizedBox(height: 14),
          if (warning != null) ...[warning, const SizedBox(height: 12)],
          if (devicesAsync.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Device scan failed: ${devicesAsync.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: SingleChildScrollView(child: left)),
                const SizedBox(width: 24),
                Expanded(child: SingleChildScrollView(child: right)),
              ])
            : ListView(children: [flashPanel, const SizedBox(height: 14), slotPanel,
                const SizedBox(height: 14), erasePanel, const SizedBox(height: 14), rebootPanel,
                const SizedBox(height: 14), advancedPanel])),
          if (_output.isNotEmpty) ...[const SizedBox(height: 12), _OutputPanel(output: _output)],
        ]);
      }),
    );
  }
}

