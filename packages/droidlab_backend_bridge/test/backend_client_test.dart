import 'dart:io';

import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String fixturePath;

  setUpAll(() {
    fixturePath = File('test/fixtures/backend_stub.py').absolute.path;
  });

  BackendClient createClient({String mode = 'normal'}) {
    return BackendClient(BackendConfig(
      executable: Platform.isWindows ? 'python' : 'python3',
      arguments: ['-u'],
      environment: {'DROIDLAB_TEST_MODE': mode},
      scriptPath: fixturePath,
      startupTimeout: const Duration(seconds: 20),
    ));
  }

  test('concurrent startup shares one backend process', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await Future.wait([client.start(), client.start(), client.start()]);

    expect(client.isRunning, isTrue);
    final result = await client.request('echo', const {});
    expect(result.data['operation'], 'echo');
  });

  test('unexpected process exit fails pending requests', () async {
    final client = createClient(mode: 'exit_on_request');
    addTearDown(client.dispose);
    await client.start();

    await expectLater(
      client.request('crash', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'process_exit',
      )),
    );
  });

  test('malformed protocol frame fails pending requests immediately', () async {
    final client = createClient(mode: 'malformed_response');
    addTearDown(client.dispose);
    await client.start();

    await expectLater(
      client.request('protocol.broken', const {},
          timeout: const Duration(seconds: 2)),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
    expect(
      client.diagnostics.where((line) => line.contains('Protocol decode error')),
      hasLength(1),
    );
    await expectLater(
      client.request('must.not.be.sent', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
  });

  test('invalid UTF-8 on protocol stdout permanently fails the connection', () async {
    final client = createClient(mode: 'invalid_utf8');
    addTearDown(client.dispose);
    await client.start();

    await expectLater(
      client.request('protocol.invalid_utf8', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
    await expectLater(
      client.request('must.not.be.sent', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
  });

  test('malformed preflight payload fails the protocol instead of leaking lazy casts', () async {
    final client = createClient(mode: 'malformed_preflight');
    addTearDown(client.dispose);
    await client.start();

    await expectLater(
      client.request('protocol.malformed_preflight', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
    await expectLater(
      client.request('must.not.be.sent', const {}),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'protocol',
      )),
    );
  });

  test('timeout cancels request and ignores a late completion', () async {
    final client = createClient(mode: 'slow');
    addTearDown(client.dispose);
    await client.start();

    await expectLater(
      client.request('slow.operation', const {},
          timeout: const Duration(milliseconds: 30)),
      throwsA(isA<BackendException>().having(
        (error) => error.code,
        'code',
        'timeout',
      )),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(client.isRunning, isTrue);
    expect(
      client.diagnostics.where((line) => line.contains('Protocol decode error')),
      isEmpty,
    );
  });

  test('dispose during startup rejects startup and closes process', () async {
    final client = createClient(mode: 'delayed_start');
    final startup = client.start();
    // Subscribe before disposal completes the startup future with an error;
    // otherwise the test runner correctly reports an unhandled async error.
    final startupFailure = expectLater(
      startup,
      throwsA(isA<BackendException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    await client.dispose();

    await startupFailure;
    expect(client.isRunning, isFalse);
    await expectLater(client.start(), throwsA(isA<BackendException>()));
  });

  test('dispose fails pending requests and closes event stream', () async {
    final client = createClient();
    await client.start();
    // Disposal may race with a final backend completion event; drain the stream
    // and assert that it closes rather than requiring it to emit no final event.
    final eventsDone = client.events.drain<void>();
    final operation = await client.startOperation('pending', const {});
    // Attach the error matcher before dispose() completes the pending future.
    final operationFailure = expectLater(
      operation.result,
      throwsA(isA<BackendException>()),
    );

    await client.dispose();

    await operationFailure;
    await eventsDone;
    expect(client.isRunning, isFalse);
  });
}
