sealed class BackendEvent {
  const BackendEvent({required this.requestId});
  final String requestId;
}
class BackendOutput extends BackendEvent {
  const BackendOutput({required super.requestId, required this.stream, required this.line});
  final String stream;
  final String line;
}
class BackendPreflight extends BackendEvent {
  const BackendPreflight({required super.requestId, required this.target, required this.command, required this.destructive});
  final String target;
  final List<String> command;
  final bool destructive;
}
class BackendAccepted extends BackendEvent {
  const BackendAccepted({required super.requestId});
}

class BackendFinished extends BackendEvent {
  const BackendFinished({required super.requestId, required this.succeeded, required this.cancelled});
  final bool succeeded;
  final bool cancelled;
}
