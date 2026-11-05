import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/operation_history.dart';

class OperationHistoryPage extends ConsumerWidget {
  const OperationHistoryPage({super.key});

  String _utc(DateTime value) {
    final time = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(operationHistoryProvider);
    final controller = ref.read(operationHistoryProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Privacy-Minimized Operation History',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.7,
              )),
            const SizedBox(height: 5),
            Text('Operation labels are allowlisted, targets are generalized, and sensitive paths/serials are omitted from disk persistence.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ])),
          OutlinedButton(
            onPressed: () => unawaited(controller.clear()),
            child: const Text('Clear Sanitized Audit Log'),
          ),
        ]),
      ),
      Divider(height: 1, color: colors.outlineVariant),
      const SizedBox(height: 20),
      if (controller.persistenceError != null)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
          'History persistence warning: ${controller.persistenceError}',
          style: TextStyle(color: colors.error),
        )),
      Expanded(child: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load operation history: $error')),
        data: (records) => records.isEmpty
          ? const Center(child: Text('No operations have been recorded yet.'))
          : Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  color: colors.surfaceContainerHighest,
                  child: const Row(children: [
                    SizedBox(width: 175, child: Text('Timestamp (UTC)')),
                    SizedBox(width: 190, child: Text('Allowlisted Operation')),
                    SizedBox(width: 145, child: Text('Target Category')),
                    Expanded(child: Text('Sanitized Outcome Summary')),
                  ]),
                ),
                Divider(height: 1, color: colors.outlineVariant),
                Expanded(child: ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: colors.outlineVariant),
                  itemBuilder: (context, index) {
                    final item = records[index];
                    final color = switch (item.status) {
                      'completed' => colors.tertiary,
                      'cancelled' => colors.secondary,
                      _ => colors.error,
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 175, child: Text(_utc(item.timestamp),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant, fontFamily: 'monospace',
                          ))),
                        SizedBox(width: 190, child: Text(item.operation,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700, fontFamily: 'monospace',
                          ))),
                        SizedBox(width: 145, child: Text(item.target,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'))),
                        Expanded(child: RichText(text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall,
                          children: [
                            TextSpan(text: item.status.toUpperCase(),
                              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                            TextSpan(text: ' · ${item.summary}'),
                          ],
                        ))),
                      ]),
                    );
                  },
                )),
              ]),
            ),
      )),
    ]);
  }
}
