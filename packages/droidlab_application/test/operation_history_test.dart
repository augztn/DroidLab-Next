import 'package:droidlab_application/droidlab_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
