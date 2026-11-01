import 'dart:convert';
import 'dart:io';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Returns a deliberately non-diagnostic failure summary for local history.
///
/// Backend exception messages can contain command output, filesystem paths,
/// device identifiers or user-supplied arguments. Keep those details out of
/// the persistent history; users can inspect the live operation console when
/// they need the full diagnostic context.
/// Keeps command arguments and user-provided suffixes out of persisted labels.
String historyOperationLabel(String operation) {
  final label = operation.split(':').first.trim();
  if (label.isEmpty) return 'Operation';
  return label.length <= 80 ? label : label.substring(0, 80);
}

String operationFailureSummary(Object error) {
  if (error is BackendException && error.code == 'cancelled') {
    return 'Operation cancelled.';
  }
  return 'Operation failed. Detailed error text was omitted from local history.';
}

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
  static const _schemaVersion = 1;
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
      // Version 0 was a bare JSON array. Continue reading it so existing
      // installations retain their history after upgrading.
      final List<dynamic> serializedRecords;
      if (decoded is List<dynamic>) {
        serializedRecords = decoded;
      } else if (decoded is Map<String, dynamic>) {
        final version = decoded['schema_version'];
        if (version != _schemaVersion) {
          throw FormatException('Unsupported operation history schema version: $version');
        }
        final recordsValue = decoded['records'];
        if (recordsValue is! List<dynamic>) {
          throw const FormatException('Operation history records must be a JSON array.');
        }
        serializedRecords = recordsValue;
      } else {
        throw const FormatException('Operation history file must contain a JSON array or versioned object.');
      }
      final records = serializedRecords.map((value) {
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
      jsonEncode({
        'schema_version': _schemaVersion,
        'records': records.map((record) => record.toJson()).toList(),
      }),
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
      operation: historyOperationLabel(operation),
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
      summary: operationFailureSummary(error),
    ));
    rethrow;
  }
}
