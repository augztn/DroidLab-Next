import 'package:droidlab_application/src/pages/fastboot_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FastbootCommand.parse', () {
    test('accepts argument-only commands', () {
      final parsed = FastbootCommand.parse('getvar product');
      expect(parsed, isNotNull);
      expect(parsed!.arguments, ['getvar', 'product']);
      expect(parsed.isDiscovery, isFalse);
    });

    test('strips bare executable names', () {
      final parsed = FastbootCommand.parse('fastboot.exe devices');
      expect(parsed, isNotNull);
      expect(parsed!.arguments, ['devices']);
      expect(parsed.isDiscovery, isTrue);
    });

    test('strips quoted Windows executable paths containing spaces', () {
      final parsed = FastbootCommand.parse(
        '"C:\Android SDK\platform-tools\fastboot.exe" -s SERIAL getvar product',
      );
      expect(parsed, isNotNull);
      expect(parsed!.arguments, ['-s', 'SERIAL', 'getvar', 'product']);
      expect(parsed.hasExplicitSerial, isTrue);
      expect(parsed.isDiscovery, isFalse);
    });

    test('strips unquoted executable paths', () {
      final parsed = FastbootCommand.parse(
        r'C:\Android\platform-tools\fastboot.exe devices',
      );
      expect(parsed, isNotNull);
      expect(parsed!.arguments, ['devices']);
      expect(parsed.isDiscovery, isTrue);
    });

    test('does not strip executable-like suffixes', () {
      final parsed = FastbootCommand.parse('myfastboot devices');
      expect(parsed, isNotNull);
      expect(parsed!.arguments, ['myfastboot', 'devices']);
      expect(parsed.isDiscovery, isFalse);
    });

    test('recognizes explicit selector before discovery verb', () {
      final parsed = FastbootCommand.parse('fastboot -s SERIAL devices');
      expect(parsed, isNotNull);
      expect(parsed!.hasExplicitSerial, isTrue);
      expect(parsed.isDiscovery, isFalse);
    });

    test('preserves quoted arguments containing spaces in preview', () {
      final parsed = FastbootCommand.parse(
        r'flash boot "C:\Images\my boot.img"',
      );
      expect(parsed, isNotNull);
      expect(parsed!.preview, r'flash boot "C:\Images\my boot.img"');
    });

    test('rejects unterminated quotes', () {
      expect(FastbootCommand.parse('flash boot "my image.img'), isNull);
    });

    test('rejects missing selector values', () {
      expect(FastbootCommand.parse('-s devices'), isNull);
    });
  });
}
