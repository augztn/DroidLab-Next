part of 'feature_pages.dart';

class DeviceManagerPage extends ConsumerStatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  ConsumerState<DeviceManagerPage> createState() => _DeviceManagerPageState();
}

class _DeviceManagerPageState extends ConsumerState<DeviceManagerPage> {
  String? _selectedSerial;
  String? _metadataSerial;
  Future<Map<String, dynamic>>? _metadataFuture;

  Future<Map<String, dynamic>> _readMetadata(String serial) async {
    final result = await ref.read(backendClientProvider).request(
      'device.info',
      {'serial': serial},
    );
    final raw = result.data['metadata'];
    return raw is Map<String, dynamic> ? raw : const {};
  }

  String _displayValue(Map<String, dynamic> values, String key, [String fallback = '—']) {
    final value = values[key];
    return value == null || value.toString().isEmpty ? fallback : value.toString();
  }

  Widget _property(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ))),
      const SizedBox(width: 12),
      Flexible(child: SelectableText(value, textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceListProvider);
    final globalTarget = ref.watch(selectedTargetSerialProvider);
    return _PageFrame(
      title: 'Device Manager & Transport State',
      subtitle: 'Distinguishes ADB, Recovery, Sideload, Bootloader Fastboot, and Userspace Fastbootd',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(deviceListProvider),
          icon: const Icon(Icons.usb, size: 17),
          label: const Text('Probe Hardware'),
        ),
      ],
      child: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPanel(
          message: error.toString(),
          retry: () => ref.invalidate(deviceListProvider),
        ),
        data: (data) {
          final list = (data['devices'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final warnings = (data['warnings'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          if (list.isEmpty) {
            return Column(children: [
              const Expanded(child: _EmptyPanel(
                icon: Icons.usb_off,
                title: 'No Android devices detected',
                message: 'Connect a device with USB debugging or Fastboot enabled.',
              )),
              for (final warning in warnings)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${warning['transport']}: ${warning['message']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ]);
          }

          if (globalTarget == null && list.length == 1) {
            final onlySerial = list.single['serial']?.toString();
            if (onlySerial != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && ref.read(selectedTargetSerialProvider) == null) {
                  ref.read(selectedTargetSerialProvider.notifier).state = onlySerial;
                }
              });
            }
          }
          final preferredSerial = globalTarget ?? _selectedSerial;
          final selected = list.firstWhere(
            (device) => device['serial'] == preferredSerial,
            orElse: () => list.first,
          );
          final serial = selected['serial']?.toString() ?? '';
          if (_metadataSerial != serial) {
            _metadataSerial = serial;
            _metadataFuture = _readMetadata(serial);
          }
          final metadataFuture = _metadataFuture;

          Widget deviceCard(Map<String, dynamic> device) {
            final targetSerial = device['serial']?.toString() ?? 'unknown';
            final transport = device['transport']?.toString() ?? 'unknown';
            final state = device['state']?.toString() ?? 'unknown';
            final model = device['model']?.toString() ??
                device['product']?.toString() ?? 'Android device';
            final active = targetSerial == preferredSerial;
            final product = device['product']?.toString();
            final mode = device['mode']?.toString();
            final version = device['android_version']?.toString();
            final summary = <String>[
              if (version != null && version.isNotEmpty) 'Android $version',
              if (mode != null && mode.isNotEmpty) mode,
              if (product != null && product.isNotEmpty) product,
              'State: $state',
            ].join(' · ');
            return Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  width: active ? 1.2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(transport.startsWith('fastboot') ? Icons.memory : Icons.phone_android,
                      color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(model, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('${transport.toUpperCase()} · $targetSerial',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        )),
                    ])),
                    if (active)
                      FilledButton.tonal(onPressed: null, child: const Text('Active Target'))
                    else
                      OutlinedButton(onPressed: () {
                        setState(() => _selectedSerial = targetSerial);
                        ref.read(selectedTargetSerialProvider.notifier).state = targetSerial;
                      }, child: const Text('Select Target')),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        ref.read(selectedTargetSerialProvider.notifier).state = targetSerial;
                        context.go(
                          transport == 'fastboot' || transport == 'fastbootd' ? '/fastboot' : '/adb',
                        );
                      },
                      child: const Text('Open Toolkit'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(summary, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text('Transport State', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Text(transport, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ),
                    const Spacer(),
                    Icon(transport.startsWith('fastboot') ? Icons.lock_open : Icons.usb,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(state, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy serial',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: targetSerial))),
                      icon: const Icon(Icons.copy, size: 17),
                    ),
                  ]),
                ]),
              ),
            );
          }

          final wide = MediaQuery.sizeOf(context).width >= 1150;
          final transports = Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Discovered Transports (${list.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                Expanded(child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => deviceCard(list[index]),
                )),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final warning in warnings)
                    Text('${warning['transport']}: ${warning['message']}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ],
              ]),
            ),
          );

          final inspector = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Transport Property Inspector',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('$serial · ${selected['transport'] ?? 'unknown'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontFamily: 'monospace',
                    )),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, dynamic>>(
                    future: metadataFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Property inspection unavailable: ${snapshot.error}',
                          style: TextStyle(color: Theme.of(context).colorScheme.error));
                      }
                      final values = snapshot.data ?? const <String, dynamic>{};
                      if (values.isEmpty) return const Text('No device properties were returned.');
                      return Column(children: [
                        for (final entry in values.entries.take(12)) ...[
                          _property(context, entry.key, entry.value?.toString() ?? '—'),
                          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                        ],
                      ]);
                    },
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Transport Guidance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Select a detected target before running device operations. ADB, Recovery, Sideload, Bootloader Fastboot, and Fastbootd are distinct transports.'),
                  const SizedBox(height: 8),
                  Text('Device changes remain guarded by operation-specific confirmation and backend transport checks.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
          ]);

          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 7, child: transports),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: SingleChildScrollView(child: inspector)),
            ]);
          }
          return ListView(children: [
            SizedBox(height: 480, child: transports),
            const SizedBox(height: 14),
            inspector,
          ]);
        },
      ),
    );
  }
}
