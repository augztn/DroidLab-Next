import 'dart:convert';

import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores a valid backup when the primary history is corrupt', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-history-recovery-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/operation_history.json');
    final backup = File('${file.path}.bak');
    await file.writeAsString('{corrupt');
    await backup.writeAsString(jsonEncode({
      'schema_version': 1,
      'records': [
        {
          'id': 'recovered',
          'timestamp': '2026-11-01T12:00:00.000Z',
          'operation': 'ADB shell private command',
          'target': 'PRIVATE-SERIAL',
          'status': 'completed',
          'summary': 'private output',
        },
      ],
    }));

    final notifier = OperationHistoryNotifier(
      supportDirectory: () async => temporary,
    );
    addTearDown(notifier.dispose);
    await notifier.record(OperationRecord(
      id: 'new',
      timestamp: DateTime.utc(2026, 11, 2),
      operation: 'Device refresh',
      target: 'serial',
      status: 'completed',
      summary: 'done',
    ));

    expect(notifier.state.requireValue.map((record) => record.id),
        containsAll(['recovered', 'new']));
    expect(await backup.exists(), isFalse);
    final corruptFiles = temporary.listSync().whereType<File>()
        .where((candidate) => candidate.path.contains('.corrupt.'));
    expect(corruptFiles, hasLength(1));
    expect(await corruptFiles.single.readAsString(), '{corrupt');
  });

  test('preserves an invalid backup when primary history is corrupt', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-history-invalid-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/operation_history.json');
    final backup = File('${file.path}.bak');
    await file.writeAsString('{primary-corrupt');
    await backup.writeAsString('{backup-corrupt');

    final notifier = OperationHistoryNotifier(
      supportDirectory: () async => temporary,
    );
    addTearDown(notifier.dispose);
    await notifier.record(OperationRecord(
      id: 'new',
      timestamp: DateTime.utc(2026, 11, 2),
      operation: 'Device refresh',
      target: 'serial',
      status: 'completed',
      summary: 'done',
    ));

    expect(await file.readAsString(), '{primary-corrupt');
    expect(await backup.readAsString(), '{backup-corrupt');
    expect(notifier.persistenceError,
        'History could not be loaded; writes are blocked to preserve the existing files.');
    await notifier.clear();
    expect(await file.readAsString(), '{primary-corrupt');
    expect(await backup.readAsString(), '{backup-corrupt');
    expect(notifier.persistenceError,
        'History could not be loaded; clear is blocked to preserve the existing files.');
  });

  test('history labels use an allowlist and omit dynamic arguments', () {
    expect(historyOperationLabel('Advanced ADB: shell cat /private/token.txt'), 'Advanced ADB');
    expect(historyOperationLabel('Fastboot flash boot'), 'Fastboot flash');
    expect(historyOperationLabel('Fastboot set active slot B'), 'Fastboot slot change');
    expect(historyOperationLabel('Payload extraction'), 'Payload extraction');
    expect(historyOperationLabel('arbitrary command token=secret'), 'Operation');
    expect(historyOperationLabel('   '), 'Operation');
  });

  test('failure summaries never persist exception details', () {
    final error = BackendException(
      'token=super-secret and /home/user/private/device.log',
      code: 'backend_error',
    );
    final summary = operationFailureSummary(error);
    expect(summary, contains('omitted'));
    expect(summary, isNot(contains('super-secret')));
    expect(summary, isNot(contains('/home/user/private')));
  });

  test('cancelled operations have a stable non-sensitive summary', () {
    expect(
      operationFailureSummary(const BackendException(
        'cancelled while processing /private/path',
        code: 'cancelled',
      )),
      'Operation cancelled.',
    );
  });

  test('JSON serialization redacts target, operation suffix and summary', () {
    final record = OperationRecord(
      id: 'op-1',
      timestamp: DateTime.utc(2026, 10, 31, 12),
      operation: 'Fastboot flash boot /private/boot.img',
      target: 'SERIAL-PRIVATE-123',
      status: 'completed',
      summary: 'Saved report to /home/user/private/report.zip',
    );

    final serialized = jsonEncode(record.toJson());

    expect(serialized, contains('Fastboot flash'));
    expect(serialized, contains('Local target'));
    expect(serialized, contains('Operation completed.'));
    expect(serialized, isNot(contains('SERIAL-PRIVATE-123')));
    expect(serialized, isNot(contains('/private/boot.img')));
    expect(serialized, isNot(contains('/home/user/private')));
  });

  test('legacy history records are sanitized when read', () {
    final restored = OperationRecord.fromJson({
      'id': 'op-legacy',
      'timestamp': '2026-10-31T12:00:00.000Z',
      'operation': 'Advanced ADB: shell cat /private/token.txt',
      'target': 'DEVICE-SECRET',
      'status': 'completed',
      'summary': 'Wrote /private/secret.log',
    });

    expect(restored.operation, 'Advanced ADB');
    expect(restored.target, 'Local target');
    expect(restored.summary, 'Operation completed.');
  });

  test('unknown statuses are normalized to failed', () {
    final restored = OperationRecord.fromJson({
      'id': 'op-legacy',
      'timestamp': '2026-10-31T12:00:00.000Z',
      'operation': 'unknown command',
      'target': 'private target',
      'status': 'unexpected',
      'summary': 'secret output',
    });

    expect(restored.operation, 'Operation');
    expect(restored.target, 'Local target');
    expect(restored.status, 'failed');
    expect(restored.summary, contains('omitted'));
  });
}
