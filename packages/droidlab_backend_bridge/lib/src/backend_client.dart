import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'backend_config.dart';
import 'backend_event.dart';
import 'backend_exception.dart';

class BackendResult {
  const BackendResult(this.data);
  final Map<String, dynamic> data;
}

class BackendOperation {
  const BackendOperation({required this.requestId, required this.result});
  final String requestId;
  final Future<BackendResult> result;
}

/// Owns a single managed backend process and its versioned JSONL connection.
class BackendClient {
  BackendClient(this.config);
  final BackendConfig config;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription, _stderrSubscription;
  final Map<String, Completer<BackendResult>> _pending = {};
  final StreamController<BackendEvent> _events = StreamController.broadcast();
  final List<String> _diagnostics = [];
  final Random _random = Random.secure();
  bool _closing = false, _disposed = false, _protocolFailed = false;

  Stream<BackendEvent> get events => _events.stream;
  List<String> get diagnostics => List.unmodifiable(_diagnostics);
  bool get isRunning => _process != null;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<void> start() {
    if (_disposed) return Future.error(const BackendException('Backend client has been disposed.'));
    if (_protocolFailed) {
      return Future.error(const BackendException(
        'Backend connection is unusable after a protocol failure. Dispose and create a new client.',
        code: 'protocol',
      ));
    }
    if (_process != null) return Future.value();
    final inFlight = _starting;
    if (inFlight != null) return inFlight;
    final future = _startProcess();
    _starting = future;
    return future.whenComplete(() {
      if (identical(_starting, future)) _starting = null;
    });
  }

  Future<void>? _starting;

  Future<void> _startProcess() async {
    try {
      final process = await Process.start(
        config.executable,
        [...config.arguments, config.scriptPath],
        runInShell: false,
        environment: config.environment.isEmpty ? null : config.environment,
      );
      _process = process;
      _closing = false;
      _stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleLine,
        onError: (Object error, StackTrace stack) => _protocolFailure(
          'Backend stdout stream failed: $error',
        ),
        onDone: _handleExit,
      );
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _recordDiagnostic(line);
      });
      final result = await request(
        'system.ping',
        const {},
        timeout: config.startupTimeout,
      );
      if (result.data['status'] != 'ok') {
        throw const BackendException(
          'Backend health check returned an invalid response.',
        );
      }
    } on BackendException {
      await _terminate();
      rethrow;
    } on Object catch (error) {
      await _terminate();
      throw BackendException('Could not start Python backend.', cause: error);
    }
  }

  Future<BackendOperation> startOperation(String operation, Map<String, dynamic> args) async {
    if (_disposed || _closing || _protocolFailed) {
      throw const BackendException('Backend is not accepting requests.', code: 'protocol');
    }
    if (_process == null) await start();
    // The protocol can fail while asynchronous startup is completing.
    if (_protocolFailed) {
      throw const BackendException(
        'Backend connection is unusable after a protocol failure.',
        code: 'protocol',
      );
    }
    // Disposal or an unexpected process exit can race with asynchronous start.
    // Capture and validate the process before registering/writing a request.
    final process = _process;
    if (_disposed || _closing || process == null) {
      throw const BackendException('Backend stopped before the request could be sent.');
    }
    final id = _id();
    final completer = Completer<BackendResult>();
    _pending[id] = completer;
    final payload = jsonEncode({'version': 1, 'id': id, 'operation': operation, 'args': args});
    if (utf8.encode(payload).length > config.maxLineBytes) {
      _pending.remove(id);
      throw const BackendException('Request exceeds the protocol message limit.');
    }
    try {
      process.stdin.writeln(payload);
      await process.stdin.flush();
    } on Object catch (error) {
      _pending.remove(id);
      throw BackendException('Could not write to backend stdin.', cause: error);
    }
    return BackendOperation(requestId: id, result: completer.future);
  }

  Future<BackendResult> request(String operation, Map<String, dynamic> args, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final operationHandle = await startOperation(operation, args);
    try {
      return await operationHandle.result.timeout(timeout);
    } on TimeoutException {
      await cancel(operationHandle.requestId);
      _pending.remove(operationHandle.requestId);
      throw BackendException('Backend operation $operation timed out.', code: 'timeout');
    }
  }

  Future<void> cancel(String requestId) async {
    final process = _process;
    if (process == null || _closing) return;
    final payload = jsonEncode({'version': 1, 'id': _id(), 'operation': 'system.cancel', 'args': {'request_id': requestId}});
    try {
      process.stdin.writeln(payload);
      await process.stdin.flush();
    } on Object catch (error) {
      _recordDiagnostic('Cancellation request failed: $error');
    }
  }

  void _handleLine(String line) {
    if (utf8.encode(line).length > config.maxLineBytes) {
      _protocolFailure('Backend emitted an oversized protocol message.');
      return;
    }
    try {
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic> || value['version'] != 1 ||
          value['id'] is! String || value['type'] is! String) {
        throw const FormatException('Invalid protocol envelope.');
      }
      final id = value['id'] as String;
      final type = value['type'] as String;
      final completer = _pending[id];
      if (type == 'output') {
        _events.add(BackendOutput(requestId: id, stream: value['stream'] as String? ?? 'stdout', line: value['line'] as String? ?? ''));
      } else if (type == 'preflight') {
        final rawCommand = value['command'];
        final target = value['target'];
        final destructive = value['destructive'];
        if (rawCommand is! List ||
            rawCommand.any((argument) => argument is! String) ||
            target is! String ||
            destructive is! bool) {
          throw const FormatException('Invalid preflight event payload.');
        }
        _events.add(BackendPreflight(
          requestId: id,
          target: target,
          command: List<String>.unmodifiable(rawCommand.cast<String>()),
          destructive: destructive,
        ));
      } else if (type == 'accepted') {
        _events.add(BackendAccepted(requestId: id));
      } else if (type == 'completed') {
        _events.add(BackendFinished(requestId: id, succeeded: true, cancelled: false));
        if (completer != null && !completer.isCompleted) {
          final result = value['result'];
          completer.complete(BackendResult(result is Map<String, dynamic> ? result : const {}));
          _pending.remove(id);
        }
      } else if (type == 'failed') {
        _events.add(BackendFinished(requestId: id, succeeded: false, cancelled: false));
        if (completer != null && !completer.isCompleted) {
          final error = value['error'] as Map<String, dynamic>? ?? const {};
          completer.completeError(BackendException(error['message'] as String? ?? 'Backend operation failed.', code: error['code'] as String?));
          _pending.remove(id);
        }
      } else if (type == 'cancelled') {
        _events.add(BackendFinished(requestId: id, succeeded: false, cancelled: true));
        if (completer != null && !completer.isCompleted) {
          completer.completeError(const BackendException('Operation cancelled; device-side effects may already have occurred.', code: 'cancelled'));
          _pending.remove(id);
        }
      } else {
        throw FormatException('Unknown protocol event type: $type');
      }
    } on Object catch (error) {
      _protocolFailure('Protocol decode error: $error');
    }
  }

  void _protocolFailure(String message) {
    _protocolFailed = true;
    _recordDiagnostic(message);
    // stdout is protocol-only. Once a frame is invalid, no pending request can
    // safely rely on the stream to deliver its completion.
    _failAll(BackendException(message, code: 'protocol'));
  }

  void _recordDiagnostic(String line) {
    final limit = config.maxRetainedLines;
    if (limit <= 0) return;
    _diagnostics.add(line);
    if (_diagnostics.length > limit) {
      _diagnostics.removeRange(0, _diagnostics.length - limit);
    }
  }

  void _handleExit() {
    if (_closing || _disposed) return;
    _process = null;
    _failAll(const BackendException('Backend process exited unexpectedly.', code: 'process_exit'));
  }

  void _failAll(BackendException error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> _terminate() async {
    final process = _process;
    if (process == null) return;
    _closing = true;
    try { await process.stdin.close().timeout(const Duration(seconds: 1)); } on Object {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try { await process.exitCode.timeout(const Duration(seconds: 2)); }
      on TimeoutException { process.kill(ProcessSignal.sigkill); }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _process = null;
    _closing = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll(const BackendException('Backend client disposed.'));
    final starting = _starting;
    if (starting != null) {
      try { await starting; } on Object {}
    }
    await _terminate();
    await _events.close();
  }
}
