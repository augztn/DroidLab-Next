import 'dart:io';

/// Conservative redaction for user-exported diagnostic text.
///
/// This is defense in depth, not a guarantee that logs are safe to publish.
String redactDiagnosticText(String value, {String? homeDirectory}) {
  var text = value;
  final home = homeDirectory ??
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    text = text.replaceAll(
      RegExp(RegExp.escape(home), caseSensitive: false),
      '<HOME>',
    );
  }
  text = text.replaceAllMapped(
    RegExp(r'(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', caseSensitive: false),
    (m) => m[1]! + '<REDACTED>',
  );
  text = text.replaceAllMapped(
    RegExp(r'((?:token|password|passwd|secret|api[_-]?key|client[_-]?secret)(?:\s*[:=]\s*|\s+))(?:"[^"]*"|[^\s,;]+)', caseSensitive: false),
    (m) => m[1]! + '<REDACTED>',
  );
  text = text.replaceAllMapped(
    RegExp(r'(--?(?:token|password|passwd|secret|api[-_]?key|authorization))(=|\s+)([^\s]+)', caseSensitive: false),
    (m) => m[1]! + m[2]! + '<REDACTED>',
  );
  text = text.replaceAllMapped(
    RegExp(r'([?&](?:access_token|refresh_token|token|api_key|key|password)=)[^&\s]+', caseSensitive: false),
    (m) => m[1]! + '<REDACTED>',
  );
  text = text.replaceAllMapped(
    RegExp(r'(serial|device(?:_id)?|target|imei)(\s*[:=]\s*)([A-Za-z0-9._:-]{5,})', caseSensitive: false),
    (m) => m[1]! + m[2]! + '<DEVICE_ID>',
  );
  text = text.replaceAll(
    RegExp(r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b'),
    '<MAC_ADDRESS>',
  );
  text = text.replaceAll(RegExp(r'\b\d{15}\b'), '<DEVICE_NUMBER>');
  text = text.replaceAllMapped(
    RegExp(r'((?:path|file|image|output|directory|executable|cwd)(?:_path)?\s*[:=]\s*)("[^"]*"|[^\s,;]+)', caseSensitive: false),
    (m) => m[1]! + '<PATH>',
  );
  text = text.replaceAll(
    RegExp(r'(?<![A-Za-z0-9])(?:[A-Za-z]:\\|/)(?:[^\s"<>|]+[\\/])*[^\s"<>|]+'),
    '<PATH>',
  );
  return text;
}
