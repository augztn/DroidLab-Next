import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({required this.child, required this.currentLocation, super.key});
  final Widget child;
  final String currentLocation;
  @override State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  bool _expanded = true;
  bool _consoleVisible = true;
  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('WORKSPACE', [('Dashboard','/dashboard',Icons.grid_view_rounded),('Device Manager','/devices',Icons.devices_rounded)]),
    ('FIRMWARE', [('Firmware Explorer','/firmware',Icons.folder_open_rounded),('Payload Extractor','/payload',Icons.inventory_2_outlined)]),
    ('DEVICE TOOLS', [('ADB Toolkit','/adb',Icons.terminal_rounded),('Fastboot Toolkit','/fastboot',Icons.memory_rounded)]),
    ('OBSERVABILITY', [('Logs & Diagnostics','/logs',Icons.receipt_long_rounded),('Operation History','/history',Icons.history_rounded)]),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxWidth < 1000;
    final expanded = _expanded && !compact;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(body: SafeArea(child: Column(children: [
      Container(height: 62, padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: colors.surface, border: Border(bottom: BorderSide(color: colors.outlineVariant))),
        child: Row(children: [
          IconButton(tooltip: 'Toggle navigation', onPressed: () => setState(() => _expanded = !_expanded), icon: const Icon(Icons.menu)),
          Container(width: 34,height: 34,alignment: Alignment.center,decoration: BoxDecoration(color: colors.primary,borderRadius: BorderRadius.circular(9)),child: const Text('DL',style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white))),
          const SizedBox(width: 12),
          Text('DroidLab',style: Theme.of(context).textTheme.titleLarge),
          if (!compact) ...[const SizedBox(width: 12),Text('ANDROID ENGINEERING WORKSTATION',style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1))],
          const Spacer(),
          const Chip(avatar: Icon(Icons.usb_off,size: 14),label: Text('No device')),
          const SizedBox(width: 8),
          IconButton(tooltip: 'Settings',onPressed: () => context.go('/settings'),icon: const Icon(Icons.settings_outlined)),
        ]),
      ),
      Expanded(child: Row(children: [
        AnimatedContainer(duration: const Duration(milliseconds: 160),width: expanded ? 232 : 68,color: colors.surface,
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 14),children: [
            for (final group in _groups) ...[
              if (expanded) Padding(padding: const EdgeInsets.fromLTRB(16,14,8,8),child: Text(group.$1,style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant,letterSpacing: 1))),
              for (final item in group.$2)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 2),
                  child: Tooltip(message: item.$1,child: ListTile(
                    selected: widget.currentLocation == item.$2,
                    leading: Icon(item.$3),
                    title: expanded ? Text(item.$1,maxLines: 1,overflow: TextOverflow.ellipsis) : null,
                    dense: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    onTap: () => context.go(item.$2),
                  )),
                ),
            ],
            const Divider(),
            ListTile(leading: const Icon(Icons.settings_outlined),title: expanded ? const Text('Settings') : null,onTap: () => context.go('/settings')),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: Padding(padding: EdgeInsets.all(compact ? 12 : 20),child: widget.child)),
      ])),
      if (_consoleVisible)
        Container(height: 116,decoration: BoxDecoration(color: colors.surface,border: Border(top: BorderSide(color: colors.outlineVariant))),
          child: Column(children: [
            ListTile(dense: true,leading: Icon(Icons.terminal,color: colors.primary),title: const Text('OPERATION CONSOLE'),trailing: IconButton(tooltip: 'Hide console',onPressed: () => setState(() => _consoleVisible = false),icon: const Icon(Icons.keyboard_arrow_down))),
            const Divider(height: 1),
            const Expanded(child: Padding(padding: EdgeInsets.all(12),child: Align(alignment: Alignment.topLeft,child: Text('Live backend output is available in Logs & Diagnostics.',style: TextStyle(fontFamily: 'monospace'))))),
          ]),
        )
      else
        Align(alignment: Alignment.centerRight,child: TextButton.icon(onPressed: () => setState(() => _consoleVisible = true),icon: const Icon(Icons.terminal),label: const Text('Show console'))),
    ])));
  });
}
