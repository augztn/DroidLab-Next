part of 'feature_pages.dart';

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 820;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: compact ? 2 : 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: compact ? 22 : 26,
              height: 1.18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.75,
            )),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle!, maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13.5,
                height: 1.4,
              )),
          ],
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 17),
            child: compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  heading,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft,
                      child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
                  ],
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: heading),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 20),
                    Flexible(child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
                    )),
                  ],
                ]),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 17),
          Expanded(child: child),
        ],
      );
    },
  );
}

class _TextField extends StatelessWidget {
  const _TextField({required this.controller, required this.label, this.hint, this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.output});
  final String output;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).extension<DroidLabThemeSurfaces>()?.console ??
          Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: SelectableText(
      output,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 29, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
        ]),
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 38, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 7),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700, letterSpacing: -0.6,
          )),
        ],
      ),
    ),
  );
}
