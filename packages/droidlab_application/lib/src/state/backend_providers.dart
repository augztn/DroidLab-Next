import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _userConfigPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ?? Directory.current.path;
  return '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}config.json';
}

Map<String, dynamic> _savedSettings() {
  try {
    final value = jsonDecode(File(_userConfigPath()).readAsStringSync());
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  } on FileSystemException {
    return <String, dynamic>{};
  } on FormatException {
    return <String, dynamic>{};
  }
}

String _settingPath(String envName, String settingName, String fallback) {
  final environment = Platform.environment[envName]?.trim();
  if (environment != null && environment.isNotEmpty) return environment;
  final value = _savedSettings()[settingName];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

final backendClientProvider = Provider<BackendClient>((ref) {
  final python = _settingPath(
    'DROIDLAB_PYTHON',
    'python_path',
    Platform.isWindows ? 'python' : 'python3',
  );
  final configured = _settingPath(
    'DROIDLAB_BACKEND_SCRIPT',
    'backend_path',
    '',
  );
  // Only forward explicit process-environment overrides here. Saved tool
  // locations remain in config.json and are resolved by Python for each
  // operation, so changing ADB/Fastboot/payload paths takes effect immediately
  // without keeping stale values in this long-lived backend process.
  final environment = <String, String>{
    for (final name in [
      'DROIDLAB_ADB_PATH',
      'DROIDLAB_FASTBOOT_PATH',
      'DROIDLAB_PAYLOAD_DUMPER_GO_PATH',
    ])
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
