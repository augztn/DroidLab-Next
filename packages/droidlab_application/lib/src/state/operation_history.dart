import 'dart:convert';
import 'dart:io';

import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Maps dynamic UI labels to a small allowlist before they reach local history.
String historyOperationLabel(String operation) {
  final value = operation.trim().toLowerCase();
  if (value.startsWith('advanced adb')) return 'Advanced ADB';
  if (value.startsWith('adb shell')) return 'ADB shell';
  if (value.startsWith('adb reboot')) return 'ADB reboot';
  if (value.startsWith('adb recovery sideload')) return 'ADB recovery sideload';
  if (value.startsWith('adb bugreport')) return 'ADB bugreport';
  if (value.startsWith('adb logcat')) return 'ADB logcat';
  if (value.startsWith('advanced fastboot')) return 'Advanced Fastboot';
  if (value.startsWith('fastboot flash')) return 'Fastboot flash';
  if (value.startsWith('fastboot erase')) return 'Fastboot erase';
  if (value.startsWith('fastboot reboot')) return 'Fastboot reboot';
  if (value.startsWith('fastboot wipe')) return 'Fastboot wipe';
  if (value.startsWith('fastboot set active') ||
      value.startsWith('fastboot switch')) return 'Fastboot slot change';
  if (value.startsWith('discover fastboot')) return 'Discover Fastboot partitions';
  if (value.startsWith('payload extraction')) return 'Payload extraction';
  if (value.startsWith('android package')) return 'Android package management';
  if (value.startsWith('device')) return 'Device operation';
  if (value.startsWith('system')) return 'System operation';
  if (value.startsWith('operation')) return 'Operation';
  return 'Operation';
}

/// Persisted history intentionally contains no device serials, file paths,
/// command arguments, backend output, or caller-provided success messages.
String _safeTarget(String _) => 'Local target';

String _safeSummary(String status) {
  switch (status) {
    case 'completed':
      return 'Operation completed.';
    case 'cancelled':
      return 'Operation cancelled.';
    case 'failed':
      return 'Operation failed. Detailed error text was omitted from local history.';
    default:
      return 'Operation failed. Detailed error text was omitted from local history.';
  }
}

OperationRecord _sanitizeRecord(OperationRecord record) => OperationRecord(
  id: record.id,
  timestamp: record.timestamp,
  operation: historyOperationLabel(record.operation),
  target: _safeTarget(record.target),
  status: const {'completed', 'cancelled', 'failed'}.contains(record.status)
      ? record.status
      : 'failed',
  summary: _safeSummary(record.status),
);

/// Returns a deliberately non-diagnostic failure summary for local history.
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

  Map<String, dynamic> toJson() {
    final safe = _sanitizeRecord(this);
    return {
      'id': safe.id,
      'timestamp': safe.timestamp.toIso8601String(),
      'operation': safe.operation,
      'target': safe.target,
      'status': safe.status,
      'summary': safe.summary,
    };
  }

  factory OperationRecord.fromJson(Map<String, dynamic> json) =>
      _sanitizeRecord(OperationRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        operation: json['operation'] as String,
        target: json['target'] as String? ?? '',
        status: json['status'] as String,
        summary: json['summary'] as String? ?? '',
      ));
}

class OperationHistoryNotifier extends StateNotifier<AsyncValue<List<OperationRecord>>> {
  OperationHistoryNotifier({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory,
        super(const AsyncLoading()) {
    _loaded = _load();
  }

  final Future<Directory> Function()? _supportDirectory;
  late final Future<void> _loaded;
  static const _maximumRecords = 500;
  static const _schemaVersion = 1;
  Future<void> _writeTail = Future<void>.value();
  String? persistenceError;

  Future<File> _historyFile() async {
    final directory = await (_supportDirectory?.call() ?? getApplicationSupportDirectory());
    return File('${directory.path}${Platform.pathSeparator}operation_history.json');
  }

  Future<void> _load() async {
    try {
      final file = await _historyFile();
      await _recoverHistoryFile(file);
      if (!await file.exists()) {
        state = const AsyncData([]);
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
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
      final original = serializedRecords.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid operation history record.');
        }
        return OperationRecord(
          id: value['id'] as String,
          timestamp: DateTime.parse(value['timestamp'] as String),
          operation: value['operation'] as String,
          target: value['target'] as String? ?? '',
          status: value['status'] as String,
          summary: value['summary'] as String? ?? '',
        );
      }).toList(growable: false);
      original.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final records = original.take(_maximumRecords)
          .map(_sanitizeRecord).toList(growable: false);
      state = AsyncData(records);

      // Rewrite old, potentially sensitive records immediately after migration.
      final safeSerializedRecords = records.map((record) => record.toJson()).toList();
      final requiresMigration = serializedRecords.length != records.length ||
          jsonEncode(serializedRecords) != jsonEncode(safeSerializedRecords);
      if (requiresMigration) await _persist(records);
    } on Object catch (error, stack) {
      persistenceError = 'Unable to load local operation history.';
      state = AsyncError(error, stack);
    }
  }

  Future<void> record(OperationRecord record) async {
    await _loaded;
    if (state.hasError) {
      persistenceError = 'History could not be loaded; writes are blocked to preserve the existing files.';
      return;
    }
    final safeRecord = _sanitizeRecord(record);
    final current = state.valueOrNull ?? const <OperationRecord>[];
    final records = <OperationRecord>[safeRecord, ...current]
        .take(_maximumRecords).toList(growable: false);
    state = AsyncData(records);
    _writeTail = _writeTail.catchError((_) {}).then((_) => _persist(records));
    try {
      await _writeTail;
      persistenceError = null;
    } on Object {
      persistenceError = 'Unable to save local operation history.';
    }
  }

  Future<void> clear() async {
    await _loaded;
    if (state.hasError) {
      persistenceError = 'History could not be loaded; clear is blocked to preserve the existing files.';
      return;
    }
    state = const AsyncData([]);
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      final file = await _historyFile();
      if (await file.exists()) await file.delete();
    });
    try {
      await _writeTail;
      persistenceError = null;
    } on Object {
      persistenceError = 'Unable to clear local operation history.';
    }
  }

  Future<void> _persist(List<OperationRecord> records) async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(
      jsonEncode({
        'schema_version': _schemaVersion,
        'records': records.map((record) => record.toJson()).toList(),
      }),
      flush: true,
    );

    var movedOriginal = false;
    try {
      // Windows cannot rename over an existing file. Preserve the old copy
      // until the new file is installed, and roll back on publication failure.
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) {
        await file.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(file.path);
      if (movedOriginal && await backup.exists()) await backup.delete();
    } on Object {
      if (movedOriginal && !await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _recoverHistoryFile(File file) async {
    final backup = File('${file.path}.bak');
    if (!await backup.exists()) return;

    final primaryValid = await _isValidHistoryFile(file);
    if (primaryValid) {
      await backup.delete();
      return;
    }

    if (!await _isValidHistoryFile(backup)) {
      // Keep both files untouched and block writes. With no primary, treating
      // this as an empty history would let the next write erase the backup.
      throw const FormatException(
        'The operation history backup is invalid and was preserved.',
      );
    }

    if (await file.exists()) {
      final corrupt = File(
        '${file.path}.corrupt.${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      await file.rename(corrupt.path);
    }
    await backup.rename(file.path);
  }

  Future<bool> _isValidHistoryFile(File candidate) async {
    if (!await candidate.exists()) return false;
    try {
      final decoded = jsonDecode(await candidate.readAsString());
      final List<dynamic> records;
      if (decoded is List<dynamic>) {
        records = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['schema_version'] == _schemaVersion &&
          decoded['records'] is List<dynamic>) {
        records = decoded['records'] as List<dynamic>;
      } else {
        return false;
      }
      for (final value in records) {
        if (value is! Map<String, dynamic> ||
            value['id'] is! String ||
            value['timestamp'] is! String ||
            value['operation'] is! String ||
            value['status'] is! String ||
            (value['target'] != null && value['target'] is! String) ||
            (value['summary'] != null && value['summary'] is! String)) {
          return false;
        }
        DateTime.parse(value['timestamp'] as String);
      }
      return true;
    } on Object {
      return false;
    }
  }}

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
}) {
  // WidgetRef becomes invalid when its owning page is disposed. Capture the
  // app-scoped notifier before awaiting the operation so navigation cannot
  // turn a successful device operation into a late StateError.
  final history = ref.read(operationHistoryProvider.notifier);
  return trackOperationWithHistory(
    history,
    operation: operation,
    target: target,
    action: action,
    successSummary: successSummary,
  );
}

Future<T> trackOperationWithHistory<T>(
  OperationHistoryNotifier history, {
  required String operation,
  required String target,
  required Future<T> Function() action,
  String Function(T result)? successSummary,
}) async {
  final started = DateTime.now();
  try {
    final result = await action();
    await history.record(OperationRecord(
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
    await history.record(OperationRecord(
      id: started.microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      operation: historyOperationLabel(operation),
      target: target,
      status: cancelled ? 'cancelled' : 'failed',
      summary: operationFailureSummary(error),
    ));
    rethrow;
  }
}
