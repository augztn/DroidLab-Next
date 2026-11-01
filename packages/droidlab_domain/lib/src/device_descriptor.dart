import 'dart:collection';

enum DeviceTransport { adb, fastboot, unknown }

enum DeviceConnectionState {
  device,
  recovery,
  sideload,
  unauthorized,
  offline,
  fastboot,
  unknown,
}

/// Immutable, transport-neutral identity and connection state for a device.
final class DeviceDescriptor {
  DeviceDescriptor({
    required this.serial,
    required this.transport,
    required this.state,
    Map<String, String> details = const {},
  }) : details = UnmodifiableMapView(Map<String, String>.of(details)) {
    if (serial.trim().isEmpty) {
      throw ArgumentError.value(serial, 'serial', 'must not be empty');
    }
  }

  final String serial;
  final DeviceTransport transport;
  final DeviceConnectionState state;
  final Map<String, String> details;

  bool get isReady =>
      (transport == DeviceTransport.adb && state == DeviceConnectionState.device) ||
      (transport == DeviceTransport.fastboot && state == DeviceConnectionState.fastboot);

  factory DeviceDescriptor.fromJson(Map<String, Object?> json) {
    final serial = json['serial'];
    if (serial is! String || serial.trim().isEmpty) {
      throw const FormatException('Device serial must be a non-empty string.');
    }
    final transport = switch (json['transport']) {
      'adb' => DeviceTransport.adb,
      'fastboot' => DeviceTransport.fastboot,
      _ => DeviceTransport.unknown,
    };
    final state = switch (json['state']) {
      'device' => DeviceConnectionState.device,
      'recovery' => DeviceConnectionState.recovery,
      'sideload' => DeviceConnectionState.sideload,
      'unauthorized' => DeviceConnectionState.unauthorized,
      'offline' => DeviceConnectionState.offline,
      'fastboot' => DeviceConnectionState.fastboot,
      _ => DeviceConnectionState.unknown,
    };
    final rawDetails = json['details'];
    final details = <String, String>{};
    if (rawDetails is Map) {
      for (final entry in rawDetails.entries) {
        if (entry.key is String && entry.value is String) {
          details[entry.key as String] = entry.value as String;
        }
      }
    }
    return DeviceDescriptor(
      serial: serial,
      transport: transport,
      state: state,
      details: details,
    );
  }
}
