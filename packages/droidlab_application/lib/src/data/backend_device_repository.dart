import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:droidlab_domain/droidlab_domain.dart';

/// Adapts the versioned JSONL backend response into stable domain entities.
final class BackendDeviceRepository implements DeviceRepository {
  BackendDeviceRepository(this._backend);

  final BackendClient _backend;

  @override
  Future<List<DeviceDescriptor>> discover() async {
    final result = await _backend.request(
      'devices.list',
      const {},
      timeout: const Duration(seconds: 30),
    );
    final rawDevices = result.data['devices'];
    if (rawDevices is! List) {
      throw const FormatException('Backend devices.list response has no device list.');
    }
    return List<DeviceDescriptor>.unmodifiable(
      rawDevices.whereType<Map>().map(
        (value) => DeviceDescriptor.fromJson(value.cast<String, Object?>()),
      ),
    );
  }
}
