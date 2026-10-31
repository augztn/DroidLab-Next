class BackendConfig {
  const BackendConfig({
    required this.executable,
    required this.scriptPath,
    this.arguments = const [],
    this.environment = const {},
    this.startupTimeout = const Duration(seconds: 10),
    this.maxLineBytes = 1024 * 1024,
    this.maxRetainedLines = 5000,
  });
  final String executable;
  final String scriptPath;
  final List<String> arguments;
  final Map<String, String> environment;
  final Duration startupTimeout;
  final int maxLineBytes;
  final int maxRetainedLines;
}
