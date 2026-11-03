import 'package:droidlab_application/droidlab_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts credentials in common log formats', () {
    final value = redactDiagnosticText(
      'Authorization: Bearer abc123 Authorization: Basic dXNlcjpwYXNz '
      'Proxy-Authorization: Basic cHJveHk6c2VjcmV0 Cookie: sessionid=private '
      'token=topsecret --api-key=secret password hunter2 '
      'https://example.test/?access_token=xyz',
      homeDirectory: '/home/alex',
    );

    expect(value, isNot(contains('abc123')));
    expect(value, isNot(contains('dXNlcjpwYXNz')));
    expect(value, isNot(contains('cHJveHk6c2VjcmV0')));
    expect(value, isNot(contains('sessionid=private')));
    expect(value, isNot(contains('topsecret')));
    expect(value, isNot(contains('secret')));
    expect(value, isNot(contains('hunter2')));
    expect(value, isNot(contains('access_token=xyz')));
  });

  test('redacts device identifiers, host paths, MAC and IMEI values', () {
    final value = redactDiagnosticText(
      'serial: ABCDEF123456 device_id=phone-1234 '
      'path=/home/alex/private/boot.img '
      r'file=C:\Users\Alex\private\image.img '
      'mac=AA:BB:CC:DD:EE:FF imei=123456789012345',
      homeDirectory: '/home/alex',
    );

    expect(value, isNot(contains('ABCDEF123456')));
    expect(value, isNot(contains('phone-1234')));
    expect(value, isNot(contains('/home/alex/private')));
    expect(value, isNot(contains(r'C:\Users\Alex\private')));
    expect(value, isNot(contains('AA:BB:CC:DD:EE:FF')));
    expect(value, isNot(contains('123456789012345')));
  });

  test('redacts serials in preflight targets and adb/fastboot selectors', () {
    final value = redactDiagnosticText(
      '[preflight] SERIAL-123: adb -s SERIAL-123 shell getprop\n'
      '[preflight] 192.168.1.20:5555: fastboot -s 192.168.1.20:5555 flash boot /tmp/boot.img\n'
      '[preflight] host: adb devices',
    );

    expect(value, isNot(contains('SERIAL-123')));
    expect(value, isNot(contains('192.168.1.20:5555')));
    expect(value, contains('[preflight] host:'));

    final errors = redactDiagnosticText(
      "ADB device 'ABC123' is unauthorized. Fastboot target \"192.168.1.2:5555\" is not present.",
    );
    expect(errors, isNot(contains('ABC123')));
    expect(errors, isNot(contains('192.168.1.2:5555')));
  });

  test('preserves ordinary diagnostic context', () {
    expect(
      redactDiagnosticText('Backend started; request completed in 12 ms.'),
      'Backend started; request completed in 12 ms.',
    );
  });
}
