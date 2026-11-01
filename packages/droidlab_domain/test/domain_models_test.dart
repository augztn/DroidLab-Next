import 'package:droidlab_domain/droidlab_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceDescriptor', () {
    test('parses known transport, state and immutable string details', () {
      final device = DeviceDescriptor.fromJson({
        'serial': 'device-01',
        'transport': 'adb',
        'state': 'device',
        'details': {'model': 'Pixel', 'product': 'panther'},
      });

      expect(device.transport, DeviceTransport.adb);
      expect(device.state, DeviceConnectionState.device);
      expect(device.isReady, isTrue);
      expect(device.details['model'], 'Pixel');
      expect(() => device.details['model'] = 'changed', throwsA(isA<UnsupportedError>()));
    });

    test('unknown protocol values remain representable but not ready', () {
      final device = DeviceDescriptor.fromJson({
        'serial': 'device-02',
        'transport': 'future-transport',
        'state': 'future-state',
      });

      expect(device.transport, DeviceTransport.unknown);
      expect(device.state, DeviceConnectionState.unknown);
      expect(device.isReady, isFalse);
    });

    test('rejects missing serials', () {
      expect(
        () => DeviceDescriptor.fromJson({'transport': 'adb', 'state': 'device'}),
        throwsFormatException,
      );
    });
  });

  group('PartitionDescriptor', () {
    test('parses Fastboot metadata defensively', () {
      final partition = PartitionDescriptor.fromJson({
        'name': 'system_a',
        'size': '0x100000',
        'type': 'ext4',
        'has_slot': 'yes',
        'is_logical': 'no',
      });

      expect(partition.name, 'system_a');
      expect(partition.hasSlot, isTrue);
      expect(partition.isLogical, isFalse);
    });

    test('rejects unnamed partitions and tolerates unknown flags', () {
      expect(
        () => PartitionDescriptor.fromJson({'name': ''}),
        throwsFormatException,
      );
      final partition = PartitionDescriptor.fromJson({
        'name': 'vendor',
        'has_slot': 'unknown',
      });
      expect(partition.hasSlot, isNull);
    });
  });
}
