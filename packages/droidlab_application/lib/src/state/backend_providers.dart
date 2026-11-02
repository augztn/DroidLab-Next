import 'dart:async';
import 'dart:io';

import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:droidlab_domain/droidlab_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend_device_repository.dart';
import 'app_settings.dart';

/// Explicit workstation target shared by the shell and device tool pages.
final selectedTargetSerialProvider = StateProvider<String?>((ref) => null);

final backendClientProvider = Provider<BackendClient>((ref) {
  // Only process-launch settings invalidate this provider. Theme and device
  // tool-path edits must not tear down an otherwise healthy backend process.
  final pythonOverride = ref.watch(droidLabSettingsProvider.select(
    (state) => state.valueOrNull?.pythonPath ?? '',
  ));
  final backendOverride = ref.watch(droidLabSettingsProvider.select(
    (state) => state.valueOrNull?.backendPath ?? '',
  ));
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final bundledPython = Platform.isWindows
      ? File('${executableDirectory.path}/python/python.exe')
      : Platform.isMacOS
          ? File('${executableDirectory.parent.path}/Resources/python/bin/python3')
          : null;
  final python = pythonOverride.trim().isNotEmpty
      ? pythonOverride.trim()
      : (Platform.environment['DROIDLAB_PYTHON']?.trim().isNotEmpty == true
          ? Platform.environment['DROIDLAB_PYTHON']!.trim()
          : (bundledPython?.existsSync() == true
              ? bundledPython!.path
              : (Platform.isWindows ? 'python' : 'python3')));
  final configured = backendOverride.trim().isNotEmpty
      ? backendOverride.trim()
      : (Platform.environment['DROIDLAB_BACKEND_SCRIPT']?.trim() ?? '');

  // ADB/Fastboot/payload tool overrides remain in config.json and are resolved
  // by Python for each operation. Environment overrides are forwarded only
  // when explicitly set by the launching process.
  const toolEnvironmentNames = [
    'DROIDLAB_ADB_PATH',
    'DROIDLAB_FASTBOOT_PATH',
    'DROIDLAB_PAYLOAD_DUMPER_GO_PATH',
  ];
  final environment = <String, String>{
    for (final name in toolEnvironmentNames)
      if ((Platform.environment[name] ?? '').trim().isNotEmpty)
        name: Platform.environment[name]!.trim(),
  };

  final candidates = <String>[
    if (configured.isNotEmpty) configured,
    '${Directory.current.path}/../backend/python/server.py',
    '${Directory.current.path}/backend/python/server.py',
    '${executableDirectory.path}/backend/python/server.py',
    '${executableDirectory.parent.path}/Resources/backend/server.py',
    '${executableDirectory.parent.path}/Resources/backend/python/server.py',
  ];
  final script = candidates.firstWhere(
    (candidate) => File(candidate).existsSync(),
    orElse: () => candidates.first,
  );
  final client = BackendClient(BackendConfig(
    executable: python,
    arguments: const ['-u'],
    scriptPath: script,
    environment: environment,
    startupTimeout: const Duration(seconds: 15),
  ));
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

final backendReadyProvider = FutureProvider<BackendResult>((ref) async {
  // Do not launch a backend with default paths while persisted settings are
  // still loading. The client provider then rebuilds from the loaded settings.
  await ref.watch(droidLabSettingsProvider.future);
  final client = ref.watch(backendClientProvider);
  await client.start();
  return client.request('system.tools', const {});
});

final deviceListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  await ref.watch(backendReadyProvider.future);
  final client = ref.watch(backendClientProvider);
  final result = await client.request('devices.list', const {});
  return result.data;
});


/// Returns the device-tool route only when discovery identifies one transport
/// unambiguously. Mixed ADB/Fastboot sessions and empty scans never force
/// navigation.
String? preferredDeviceToolLocation(Map<String, dynamic> data) {
  final devices = (data['devices'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  final hasAdb = devices.any((device) =>
      device['transport'] == 'adb' && device['state'] == 'device');
  final hasFastboot = devices.any((device) =>
      device['transport'] == 'fastboot' &&
      (device['state'] == 'fastboot' || device['state'] == 'fastbootd'));
  if (hasAdb == hasFastboot) return null;
  return hasAdb ? '/adb' : '/fastboot';
}

/// Typed device-discovery boundary used by features migrating off raw JSON.
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return BackendDeviceRepository(ref.watch(backendClientProvider));
});

final discoveredDevicesProvider =
    FutureProvider.autoDispose<List<DeviceDescriptor>>((ref) async {
  await ref.watch(backendReadyProvider.future);
  return ref.watch(deviceRepositoryProvider).discover();
});

/// Bounded live operation-console history shared with the Logs workspace.
final operationConsoleLinesProvider = StateProvider<List<String>>((ref) => const []);
