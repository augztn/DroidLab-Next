part of 'feature_pages.dart';

class DeviceManagerPage extends ConsumerWidget {
  const DeviceManagerPage({super.key});

  Future<void> _showDeviceInfo(BuildContext context, WidgetRef ref, String serial) async {
    try {
      final result = await ref.read(backendClientProvider).request('device.info', {'serial': serial});
      if (!context.mounted) return;
      final metadata = result.data['metadata'] as Map<String, dynamic>;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Device details · $serial'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: metadata.entries.map((entry) => ListTile(
                dense: true,
                title: Text(entry.key),
                subtitle: SelectableText(
                  entry.value?.toString().isNotEmpty == true ? entry.value.toString() : '—',
                ),
              )).toList(),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read device details: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider);
    return _PageFrame(
      title: 'Device Manager',
      subtitle: 'Discover ADB and Fastboot targets. Multiple devices are never implicitly selected.',
      actions: [
        IconButton(
          onPressed: () => ref.invalidate(deviceListProvider),
          tooltip: 'Refresh devices',
          icon: const Icon(Icons.refresh),
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
              .cast<Map<String, dynamic>>();
          final warnings = data['warnings'] as List<dynamic>? ?? const [];
          if (list.isEmpty) {
            return Column(children: [
              const Expanded(
                child: _EmptyPanel(
                  icon: Icons.usb_off,
                  title: 'No Android devices detected',
                  message: 'Connect a device with USB debugging or Fastboot enabled.',
                ),
              ),
              for (final warning in warnings)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    warning['transport'].toString() + ': ' + warning['message'].toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ]);
          }
          return ListView.separated(
            itemCount: list.length + warnings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index >= list.length) {
                final warning = warnings[index - list.length];
                return ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(warning['transport'].toString() + ' discovery warning'),
                  subtitle: Text(warning['message'].toString()),
                );
              }
              final device = list[index];
              final transport = device['transport'] as String? ?? 'unknown';
              final state = device['state'] as String? ?? 'unknown';
              final serial = device['serial'] as String? ?? 'unknown';
              final product = device['product'] as String?;
              return Card(
                child: ListTile(
                  leading: Icon(transport == 'fastboot' ? Icons.memory : Icons.phone_android),
                  title: SelectableText(serial),
                  subtitle: Text(transport + ' · ' + state + (product == null ? '' : ' · ' + product)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Device details',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _showDeviceInfo(context, ref, serial),
                    ),
                    IconButton(
                      tooltip: 'Copy serial',
                      icon: const Icon(Icons.copy),
                      onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: serial))),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

