class BackendException implements Exception {
  const BackendException(this.message, {this.code, this.cause});
  final String message;
  final String? code;
  final Object? cause;
  @override
  String toString() => 'BackendException(${code ?? 'unknown'}): $message';
}
