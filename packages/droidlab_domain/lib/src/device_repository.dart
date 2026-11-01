import 'device_descriptor.dart';

/// Boundary for device discovery. Implementations own transport/protocol details.
abstract interface class DeviceRepository {
  Future<List<DeviceDescriptor>> discover();
}
