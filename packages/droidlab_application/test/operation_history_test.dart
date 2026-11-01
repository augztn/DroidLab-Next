import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history labels omit user supplied command arguments', () {
    expect(
      historyOperationLabel('Advanced ADB: shell cat /private/token.txt'),
      'Advanced ADB',
    );
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

  test('operation records round-trip through JSON', () {
    final original = OperationRecord(
      id: 'op-1',
      timestamp: DateTime.utc(2026, 10, 31, 12),
      operation: 'Fastboot flash boot',
      target: 'DEVICE-1',
      status: 'completed',
      summary: 'Operation completed.',
    );
    final restored = OperationRecord.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.timestamp, original.timestamp);
    expect(restored.operation, original.operation);
    expect(restored.target, original.target);
    expect(restored.status, original.status);
    expect(restored.summary, original.summary);
  });
}
