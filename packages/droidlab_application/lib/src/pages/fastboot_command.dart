/// Tokenizes and classifies Fastboot command text shown in the toolkit.
///
/// The backend remains authoritative and parses the original command again
/// before dispatch.
class FastbootCommand {
  const FastbootCommand({
    required this.arguments,
    required this.hasExplicitSerial,
    required this.isDiscovery,
  });

  final List<String> arguments;
  final bool hasExplicitSerial;
  final bool isDiscovery;

  static const _discoveryVerbs = {
    'devices', 'help', '--help', '--version', 'version',
  };
  static const _optionsWithValues = {'-s', '-i', '-p', '-c', '--slot'};

  static FastbootCommand? parse(String command) {
    final tokens = _tokenize(command);
    if (tokens == null || tokens.isEmpty) return null;

    final executableName = tokens.first
        .replaceAll(r'\', '/')
        .split('/')
        .last
        .toLowerCase();
    final hasExecutable =
        executableName == 'fastboot' || executableName == 'fastboot.exe';
    final arguments = hasExecutable ? tokens.skip(1).toList() : tokens;
    if (arguments.isEmpty) {
      return const FastbootCommand(
        arguments: [],
        hasExplicitSerial: false,
        isDiscovery: false,
      );
    }

    var index = 0;
    var hasExplicitSerial = false;
    while (index < arguments.length) {
      final token = arguments[index];
      if (token == '--') {
        index++;
        break;
      }
      if (_optionsWithValues.contains(token)) {
        if (index + 1 >= arguments.length ||
            arguments[index + 1].startsWith('-')) {
          return null;
        }
        if (token == '-s') hasExplicitSerial = true;
        index += 2;
        continue;
      }
      if (token.startsWith('-s=')) {
        if (token.length == 3) return null;
        hasExplicitSerial = true;
        index++;
        continue;
      }
      if (token.startsWith('-')) {
        index++;
        continue;
      }
      break;
    }

    // A command must remain after global options. This also rejects a selector\n    // whose only apparent value was actually the final token.\n    if (index >= arguments.length) return null;\n\n    final verb = arguments[index].toLowerCase();
    return FastbootCommand(
      arguments: List.unmodifiable(arguments),
      hasExplicitSerial: hasExplicitSerial,
      isDiscovery: !hasExplicitSerial && _discoveryVerbs.contains(verb),
    );
  }

  static List<String>? _tokenize(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    String? quote;
    var tokenStarted = false;

    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (quote != null) {
        if (character == quote) {
          quote = null;
        } else if (character == r'\' &&
            quote == '"' &&
            index + 1 < input.length &&
            (input[index + 1] == '"' || input[index + 1] == r'\')) {
          current.write(input[++index]);
        } else {
          current.write(character);
        }
        tokenStarted = true;
      } else if (character == '"' || character == "'") {
        quote = character;
        tokenStarted = true;
      } else if (RegExp(r'\s').hasMatch(character)) {
        if (tokenStarted) {
          tokens.add(current.toString());
          current.clear();
          tokenStarted = false;
        }
      } else {
        current.write(character);
        tokenStarted = true;
      }
    }

    if (quote != null) return null;
    if (tokenStarted) tokens.add(current.toString());
    return tokens;
  }

  String get preview => arguments.map((argument) {
        if (!argument.contains(RegExp(r'\s')) &&
            !argument.contains('"') &&
            !argument.contains("'")) {
          return argument;
        }
        final escaped = argument
            .replaceAll('"', r'\"');
        return '"$escaped"';
      }).join(' ');
}
