part of 'feature_pages.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final devices = ref.watch(deviceListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1500;
    return _PageFrame(
      title: 'Dashboard',
      subtitle: 'Android engineering workstation overview.',
      child: GridView.count(
        crossAxisCount: wide ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: [
          _MetricCard(
            title: 'Backend',
            icon: Icons.hub,
            value: backend.when(
              data: (_) => 'Online',
              error: (_, __) => 'Unavailable',
              loading: () => 'Starting',
            ),
          ),
          _MetricCard(
            title: 'Connected devices',
            icon: Icons.devices,
            value: devices.when(
              data: (data) => ((data['devices'] as List<dynamic>? ?? const []).length).toString(),
              error: (_, __) => '—',
              loading: () => '…',
            ),
          ),
          const _MetricCard(title: 'Desktop', value: 'Ready', icon: Icons.desktop_windows),
        ],
      ),
    );
  }
}

