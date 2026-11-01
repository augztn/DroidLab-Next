import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/operation_history.dart';

class OperationHistoryPage extends ConsumerWidget {
  const OperationHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(operationHistoryProvider);
    final controller = ref.read(operationHistoryProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Operation History', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Locally persisted device and firmware operation outcomes.', style: Theme.of(context).textTheme.bodyMedium),
        ])),
        TextButton.icon(onPressed: () => unawaited(controller.clear()), icon: const Icon(Icons.delete_outline), label: const Text('Clear history')),
      ]),
      const SizedBox(height: 18),
      if (controller.persistenceError != null)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
          'History persistence warning: ${controller.persistenceError}',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        )),
      Expanded(child: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load operation history: $error')),
        data: (records) => records.isEmpty
          ? const Center(child: Text('No operations have been recorded yet.'))
          : ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = records[index];
                final color = switch (item.status) {
                  'completed' => Colors.green,
                  'cancelled' => Colors.orange,
                  _ => Theme.of(context).colorScheme.error,
                };
                return Card(child: ListTile(
                  leading: Icon(
                    item.status == 'completed' ? Icons.check_circle_outline :
                    item.status == 'cancelled' ? Icons.pause_circle_outline : Icons.error_outline,
                    color: color,
                  ),
                  title: Text(item.operation),
                  subtitle: Text('${item.target.isEmpty ? 'Host' : item.target} · ${item.summary}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    MaterialLocalizations.of(context).formatShortDate(item.timestamp),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ));
              },
            ),
      )),
    ]);
  }
}
