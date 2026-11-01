import 'dart:io';

/// Conservative redaction for user-exported diagnostic text.
///
/// Diagnostics are untrusted and may contain identifiers, credentials, and
/// host paths. This is a defense-in-depth filter, not a guarantee that a log
/// is safe to publish; callers must still let users review exports.
String redactDiagnosticText(String value, {String? homeDirectory}) {
  var redacted = value;
  final home = homeDirectory ??
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    redacted = redacted.replaceAll(
      RegExp(RegExp.escape(home), caseSensitive: false),
      '<HOME>',
    );
  }
  final patterns = <(RegExp, String)>[
    (RegExp(r'(authorization\\s*[:=]\\s*bearer\\s+)[^\\s,;]+', caseSensitive: false), r'\$1<REDACTED>'),
    (RegExp(r'((?:token|password|passwd|secret|api[_-]?key|client[_-]?secret)(?:\\s*[:=]\\s*|\\s+))(?:"[^"]*"|\\x27[^\\x27]*\\x27|[^\\s,;]+)', caseSensitive: false), r'\$1<REDACTED>'),
    (RegExp(r'(--?(?:token|password|passwd|secret|api[-_]?key|authorization))(=|\\s+)([^\\s]+)', caseSensitive: false), r'\$1\$2<REDACTED>'),
    (RegExp(r'([?&](?:access_token|refresh_token|token|api_key|key|password)=)[^&\\s]+', caseSensitive: false), r'\$1<REDACTED>'),
    (RegExp(r'(serial|device(?:_id)?|target|imei)(\\s*[:=]\\s*)([A-Za-z0-9._:-]{5,})', caseSensitive: false), r'\$1\$2<DEVICE_ID>'),
    (RegExp(r'\\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\\b'), '<MAC_ADDRESS>'),
    (RegExp(r'\\b\\d{15}\\b'), '<DEVICE_NUMBER>'),
    (RegExp(r'((?:path|file|image|output|directory|executable|cwd)(?:_path)?\\s*[:=]\\s*)(?:"[^"]+"|\\x27[^\\x27]*\\x27|[^\\s,;]+)', caseSensitive: false), r'\$1<PATH>'),
    (RegExp(r'(?<![A-Za-z0-9])(?:[A-Za-z]:\\\\|/)(?:[^\\s"\\x27<>|]+[\\\\/])*[^\\s"\\x27<>|]+'), '<PATH>'),
  ];
  for (final (pattern, replacement) in patterns) {
    redacted = redacted.replaceAllMapped(pattern, (match) {
      return replacement.replaceAllMapped(
        RegExp(r'\\\$(\\d+)'),
        (group) => match.group(int.parse(group.group(1)!)) ?? '',
      );
    });
  }
  return redacted;
}
