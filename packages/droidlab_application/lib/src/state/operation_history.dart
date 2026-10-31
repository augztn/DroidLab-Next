import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class OperationRecord {
  const OperationRecord({
    required this.id,
    required this.timestamp,
    required this.operation,
    required this.target,
    required this.status,
    required this.summary,
  });
  final String id;
  final DateTime timestamp;
  final String operation;
  final String target;
  final String status;
  final String summary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'operation': operation,
    'target': target,
    'status': status,
    'summary': summary,
  };

  factory OperationRecord.fromJson(Map<String, dynamic> json) => OperationRecord(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    operation: json['operation'] as String,
    target: json['target'] as String? ?? '',
    status: json['status'] as String,
    summary: json['summary'] as String? ?? '',
  );
}

class OperationHistoryNotifier extends StateNotifier<AsyncValue<List<OperationRecord>>> {
  OperationHistoryNotifier() : super(const AsyncLoading()) {
    _loaded = _load();
  }

  late final Future<void> _loaded;
  static const _maximumRecords = 500;
  Future<void> _writeTail = Future<void>.value();
  String? persistenceError;

  Future<File> _historyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}operation_history.json');
  }

  Future<void> _load() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) {
        state = const AsyncData([]);
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) {
        throw const FormatException('Operation history file must contain a JSON array.');
      }
      final records = decoded.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid operation history record.');
        }
        return OperationRecord.fromJson(value);
      }).toList(growable: false);
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = AsyncData(records.take(_maximumRecords).toList(growable: false));
    } on Object catch (error, stack) {
      persistenceError = error.toString();
      state = AsyncError(error, stack);
    }
  }

  Future<void> record(OperationRecord record) async {
    await _loaded;
    final current = state.valueOrNull ?? const <OperationRecord>[];
    final records = <OperationRecord>[record, ...current]
        .take(_maximumRecords)
        .toList(growable: false);
    state = AsyncData(records);
    _writeTail = _writeTail.catchError((_) {}).then((_) => _persist(records));
    try {
      await _writeTail;
      persistenceError = null;
    } on Object catch (error) {
      persistenceError = error.toString();
    }
  }

  Future<void> clear() async {
    await _loaded;
    state = const AsyncData([]);
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      final file = await _historyFile();
      if (await file.exists()) await file.delete();
    });
    try {
      await _writeTail;
      persistenceError = null;
    } on Object catch (error) {
      persistenceError = error.toString();
    }
  }

  Future<void> _persist(List<OperationRecord> records) async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(records.map((record) => record.toJson()).toList()),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}

final operationHistoryProvider = StateNotifierProvider<
    OperationHistoryNotifier, AsyncValue<List<OperationRecord>>>(
  (ref) => OperationHistoryNotifier(),
);

Future<T> trackOperation<T>(
  WidgetRef ref, {
  required String operation,
  required String target,
  required Future<T> Function() action,
  String Function(T result)? successSummary,
}) async {
  final started = DateTime.now();
  try {
    final result = await action();
    await ref.read(operationHistoryProvider.notifier).record(OperationRecord(
      id: started.microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      operation: operation,
      target: target,
      status: 'completed',
      summary: successSummary?.call(result) ?? 'Operation completed.',
    ));
    return result;
  } on Object catch (error) {
    final cancelled = error is BackendException && error.code == 'cancelled';
    await ref.read(operationHistoryProvider.notifier).record(OperationRecord(
      id: started.microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      operation: operation,
      target: target,
      status: cancelled ? 'cancelled' : 'failed',
      summary: error.toString(),
    ));
    rethrow;
  }
}
