part of 'feature_pages.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _githubUrl = 'https://github.com/augztn';
  static const _instagramUrl = 'https://www.instagram.com/augztn/';

  Future<void> _openExternalLink(BuildContext context, String url) async {
    try {
      if (Platform.isWindows) {
        await Process.start(
          'rundll32.exe',
          ['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else {
        throw UnsupportedError('Opening external links is not supported on this platform.');
      }
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link. Please check your default browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}';
    final colors = Theme.of(context).colorScheme;

    Widget panel({required String title, required Widget child}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );

    final developer = panel(
      title: 'Developer',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: colors.primaryContainer,
            child: Icon(Icons.code_rounded, size: 27, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('augztn', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('Developer of DroidLab', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            ],
          )),
        ]),
        const SizedBox(height: 16),
        const Text('Follow the project and connect with the developer through these public profiles.'),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: () => _openExternalLink(context, _githubUrl),
            icon: const Icon(Icons.code_rounded, size: 18),
            label: const Text('GitHub'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openExternalLink(context, _instagramUrl),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Instagram'),
          ),
        ]),
        const SizedBox(height: 8),
        SelectableText('github.com/augztn', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        SelectableText('instagram.com/augztn', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ]),
    );

    final principles = panel(
      title: 'Architectural Principles',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DroidLab separates presentation and confirmation state from external process execution. The UI layer never invokes host shell commands directly; it dispatches correlated JSONL v1 requests over stdio to a headless Python backend.'),
        const SizedBox(height: 14),
        const Text('Every device mutation requires an explicit serial, a fresh transport scan, discrete argument arrays, and an immutable confirmation envelope verified on both sides of the boundary.'),
        const SizedBox(height: 18),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.computer),
          title: const Text('Platform'),
          subtitle: Text(platform),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined),
          title: Text('Local-first'),
          subtitle: Text('Device operations and diagnostic files are handled on this computer.'),
        ),
      ]),
    );

    final topology = panel(
      title: 'Workspace Package Topology',
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _TopologyLine('apps/desktop', 'Native runner & composition root'),
        _TopologyLine('packages/droidlab_domain', 'Immutable Device & Partition entities'),
        _TopologyLine('packages/droidlab_backend_bridge', 'JSONL v1 process lifecycle'),
        _TopologyLine('packages/droidlab_design_system', 'Theme tokens & Material 3'),
        _TopologyLine('packages/droidlab_application', 'Riverpod state, GoRouter & pages'),
        _TopologyLine('backend/python', 'Tool resolver, staging & guarded operations'),
      ]),
    );

    return _PageFrame(
      title: 'About DroidLab',
      subtitle: 'Built by augztn · Apache-2.0 License · Flutter & Python',
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(children: [
            developer,
            const SizedBox(height: 14),
            principles,
            const SizedBox(height: 14),
            topology,
          ]);
        }
        return ListView(children: [
          developer,
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: principles),
            const SizedBox(width: 24),
            Expanded(child: topology),
          ]),
        ]);
      }),
    );
  }
}

class _TopologyLine extends StatelessWidget {
  const _TopologyLine(this.path, this.description);
  final String path;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 245, child: SelectableText(path,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'))),
      Expanded(child: Text('— $description',
        style: Theme.of(context).textTheme.bodySmall)),
    ]),
  );
}
