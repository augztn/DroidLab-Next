import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_application/src/state/backend_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('router provider initializes at dashboard', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
  });
}

  test('device discovery selects ADB route when only authorized ADB is present', () {
    expect(
      preferredDeviceToolLocation({
        'devices': [
          {'serial': 'ADB-1', 'transport': 'adb', 'state': 'device'},
        ],
      }),
      '/adb',
    );
  });

  test('device discovery selects Fastboot route for bootloader or fastbootd', () {
    for (final state in ['fastboot', 'fastbootd']) {
      expect(
        preferredDeviceToolLocation({
          'devices': [
            {'serial': 'FB-1', 'transport': 'fastboot', 'state': state},
          ],
        }),
        '/fastboot',
      );
    }
  });

  test('mixed or empty device discovery never forces a tool route', () {
    expect(preferredDeviceToolLocation({'devices': []}), isNull);
    expect(
      preferredDeviceToolLocation({
        'devices': [
          {'serial': 'ADB-1', 'transport': 'adb', 'state': 'device'},
          {'serial': 'FB-1', 'transport': 'fastboot', 'state': 'fastboot'},
        ],
      }),
      isNull,
    );
  });
