import 'dart:async';
import 'dart:io';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final backendClientProvider = Provider<BackendClient>((ref) {
  final python = Platform.environment['DROIDLAB_PYTHON'] ??
      (Platform.isWindows ? 'python' : 'python3');
  final configured = Platform.environment['DROIDLAB_BACKEND_SCRIPT'];
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final candidates = <String>[
    if (configured != null && configured.isNotEmpty) configured,
    '${Directory.current.path}/../../backend/python/server.py',
    '${Directory.current.path}/backend/python/server.py',
    '${executableDirectory.path}/backend/python/server.py',
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
