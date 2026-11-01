import 'package:droidlab_application/src/state/backend_providers.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeBackendClient extends BackendClient {
  FakeBackendClient()
      : super(const BackendConfig(
          executable: 'unused',
          scriptPath: 'unused',
        ));

  @override
  Stream<BackendEvent> get events => const Stream<BackendEvent>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<BackendResult> request(
    String operation,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    return const BackendResult({
      'status': 'ok',
      'devices': <dynamic>[],
    });
  }

  @override
  Future<BackendOperation> startOperation(
    String operation,
    Map<String, dynamic> args,
  ) async {
    return BackendOperation(
      requestId: 'test-operation',
      result: Future.value(
        const BackendResult({'status': 'ok'}),
      ),
    );
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> dispose() async {}
}

List<Override> testBackendOverrides() => [
      backendClientProvider.overrideWith((ref) {
        final client = FakeBackendClient();
        ref.onDispose(client.dispose);
        return client;
      }),
      backendReadyProvider.overrideWith(
        (ref) async => const BackendResult({'status': 'ok'}),
      ),
      deviceListProvider.overrideWith(
        (ref) async => {'devices': <dynamic>[]},
      ),
    ];
