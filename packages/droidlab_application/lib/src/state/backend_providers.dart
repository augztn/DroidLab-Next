import 'dart:async';
import 'dart:io';

import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

final backendClientProvider = Provider<BackendClient>((ref) {
  final settingsState = ref.watch(droidLabSettingsProvider);
  final settings = settingsState.requireValue;
  final python = settings.pythonPath.trim().isNotEmpty
      ? settings.pythonPath.trim()
      : (Platform.environment['DROIDLAB_PYTHON']?.trim().isNotEmpty == true
          ? Platform.environment['DROIDLAB_PYTHON']!.trim()
          : (Platform.isWindows ? 'python' : 'python3'));
  final configured = settings.backendPath.trim().isNotEmpty
      ? settings.backendPath.trim()
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

  final executableDirectory = File(Platform.resolvedExecutable).parent;
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
