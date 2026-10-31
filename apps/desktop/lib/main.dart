import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DroidLabApp()));
}

class DroidLabApp extends ConsumerWidget {
  const DroidLabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'DroidLab',
      debugShowCheckedModeBanner: false,
      theme: DroidLabTheme.dark(),
      routerConfig: router,
    );
  }
}

/// Desktop shell: navigation, device telemetry, workspace and shared console.
class DesktopShell extends StatefulWidget {
  const DesktopShell({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  bool _expanded = true;
  bool _consoleVisible = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;
        final expanded = _expanded && !compact;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _AppHeader(
                  onToggleSidebar: () => setState(() => _expanded = !_expanded),
                  compact: compact,
                ),
                Expanded(
                  child: Row(
                    children: [
                      _NavigationSidebar(
                        expanded: expanded,
                        onDestinationSelected: (route) => context.go(route),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 12 : 20),
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_consoleVisible)
                  const _ConsolePanel()
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _consoleVisible = true),
                      icon: const Icon(Icons.terminal),
                      label: const Text('Show console'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.onToggleSidebar,
    required this.compact,
  });

  final VoidCallback onToggleSidebar;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Toggle navigation',
            onPressed: onToggleSidebar,
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'DL',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'DroidLab',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: .2,
                ),
          ),
          const SizedBox(width: 10),
          if (!compact)
            Text(
              'ANDROID ENGINEERING WORKSTATION',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
            ),
          const Spacer(),
          const _DeviceStatusChip(),
          const SizedBox(width: 12),
          const _BackendStatusChip(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusChip extends StatelessWidget {
  const _DeviceStatusChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'No device is selected',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.usb_off_rounded, size: 15, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('No device', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _BackendStatusChip extends StatelessWidget {
  const _BackendStatusChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Backend health has not been checked yet',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: colors.tertiary),
            const SizedBox(width: 8),
            Text('Backend idle', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.expanded,
    required this.onDestinationSelected,
  });

  final bool expanded;
  final ValueChanged<String> onDestinationSelected;

  static const _groups = <_NavigationGroup>[
    _NavigationGroup('WORKSPACE', [
      _NavigationDestination('Dashboard', '/dashboard', Icons.grid_view_rounded),
      _NavigationDestination('Device Manager', '/devices', Icons.devices_rounded),
    ]),
    _NavigationGroup('FIRMWARE', [
      _NavigationDestination('Firmware Explorer', '/firmware', Icons.folder_open_rounded),
      _NavigationDestination('Payload Extractor', '/payload', Icons.inventory_2_outlined),
    ]),
    _NavigationGroup('DEVICE TOOLS', [
      _NavigationDestination('ADB Toolkit', '/adb', Icons.terminal_rounded),
      _NavigationDestination('Fastboot Toolkit', '/fastboot', Icons.memory_rounded),
    ]),
    _NavigationGroup('OBSERVABILITY', [
      _NavigationDestination('Logs & Diagnostics', '/logs', Icons.receipt_long_rounded),
      _NavigationDestination('Operation History', '/history', Icons.history_rounded),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currentLocation = GoRouterState.of(context).matchedLocation;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? 248 : 72,
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          for (final group in _groups) ...[
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                child: Text(
                  group.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                ),
              )
            else
              const SizedBox(height: 8),
            for (final destination in group.destinations)
              _NavigationItem(
                destination: destination,
                expanded: expanded,
                selected: currentLocation == destination.route,
                onTap: () => onDestinationSelected(destination.route),
              ),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          _NavigationItem(
            destination: const _NavigationDestination(
              'Settings',
              '/settings',
              Icons.settings_outlined,
            ),
            expanded: expanded,
            selected: currentLocation == '/settings',
            onTap: () => onDestinationSelected('/settings'),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.destination,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final _NavigationDestination destination;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 8, vertical: 2),
      child: Tooltip(
        message: expanded ? '' : destination.label,
        child: Material(
          color: selected ? colors.primary.withOpacity(.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment:
                    expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    destination.icon,
                    size: 19,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: selected ? colors.primary : colors.onSurface,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                  if (!expanded) const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 156,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Text('OPERATION CONSOLE', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text(
                  'No active process',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'DroidLab desktop shell initialized. Backend operations are disabled until the '
                  'versioned bridge is implemented.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationGroup {
  const _NavigationGroup(this.label, this.destinations);

  final String label;
  final List<_NavigationDestination> destinations;
}

class _NavigationDestination {
  const _NavigationDestination(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}
