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

  test('device manager requires a target when multiple devices are connected', () {
    final first = {'serial': 'DEVICE-1', 'transport': 'adb', 'state': 'device'};
    final second = {'serial': 'DEVICE-2', 'transport': 'fastboot', 'state': 'fastboot'};

    expect(resolveDeviceManagerTarget([first, second], null), isNull);
    expect(resolveDeviceManagerTarget([first], null), same(first));
    expect(resolveDeviceManagerTarget([first, second], 'DEVICE-2'), same(second));
    expect(resolveDeviceManagerTarget([first, second], 'MISSING'), isNull);
  });

  test('dashboard never falls back to the first device when selection is ambiguous', () {
    final first = {'serial': 'ADB-1', 'transport': 'adb', 'state': 'device'};
    final second = {'serial': 'ADB-2', 'transport': 'adb', 'state': 'device'};
    final fastboot = {'serial': 'FB-1', 'transport': 'fastboot', 'state': 'fastboot'};

    expect(resolveDashboardAdbTarget([first, second], null), isNull);
    expect(resolveDashboardAdbTarget([first], null), same(first));
    expect(resolveDashboardAdbTarget([first, second], 'ADB-2'), same(second));
    expect(resolveDashboardAdbTarget([first, second], 'MISSING'), isNull);
    expect(resolveDashboardAdbTarget([first, fastboot], 'FB-1'), isNull);
  });

  test('Fastboot readiness accepts bootloader and userspace Fastbootd only', () {
    for (final state in ['fastboot', 'fastbootd']) {
      expect(
        isFastbootDeviceReady({'transport': 'fastboot', 'state': state}),
        isTrue,
      );
    }
    expect(
      isFastbootDeviceReady({'transport': 'adb', 'state': 'device'}),
      isFalse,
    );
    expect(
      isFastbootDeviceReady({'transport': 'fastboot', 'state': 'unauthorized'}),
      isFalse,
    );
    expect(isFastbootDeviceReady(null), isFalse);
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
}
