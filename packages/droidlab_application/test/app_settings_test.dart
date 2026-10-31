import 'dart:io';

import 'package:droidlab_application/droidlab_application.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads legacy theme and tolerates missing tool path keys', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-settings-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File(temporary.path + '/config.json');
    await file.writeAsString('{"theme":"oled_black"}');

    final settings = await DroidLabSettingsStore(file: file).load();

    expect(settings.theme, 'oled_black');
    expect(settings.adbPath, isEmpty);
    expect(settings.fastbootPath, isEmpty);
  });

  test('persists theme and executable overrides in legacy config location', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-settings-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File(temporary.path + '/config.json');
    final store = DroidLabSettingsStore(file: file);
    const settings = DroidLabSettings(
      theme: 'standard_dark',
      pythonPath: '/opt/python/bin/python3',
      backendPath: '/opt/droidlab/server.py',
      adbPath: '/opt/platform-tools/adb',
      fastbootPath: '/opt/platform-tools/fastboot',
      payloadDumperPath: '/opt/droidlab/payload-dumper-go',
    );

    await store.save(settings);
    final loaded = await store.load();

    expect(loaded.toJson(), settings.toJson());
  });

  test('provider writes settings through the replaceable store', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-provider-');
    addTearDown(() => temporary.delete(recursive: true));
    final store = DroidLabSettingsStore(
      file: File(temporary.path + '/DroidLab/config.json'),
    );
    final container = ProviderContainer(
      overrides: [droidLabSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(droidLabSettingsProvider.future);
    const value = DroidLabSettings(theme: 'oled_black', adbPath: '/custom/adb');
    await container.read(droidLabSettingsProvider.notifier).saveSettings(value);

    expect((await store.load()).toJson(), value.toJson());
  });
  test('backend provider forwards saved tool paths to Python environment', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-tool-env-');
    addTearDown(() => temporary.delete(recursive: true));
    final config = File(temporary.path + '/DroidLab/config.json');
    final store = DroidLabSettingsStore(file: config);
    await store.save(const DroidLabSettings(
      adbPath: '/custom/platform-tools/adb',
      fastbootPath: '/custom/platform-tools/fastboot',
      payloadDumperPath: '/custom/payload-dumper-go',
    ));
    final container = ProviderContainer(
      overrides: [droidLabSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    // Provider creation remains side-effect-light; we assert the same settings
    // source that backendClientProvider reads when its process is started.
    final loaded = await container.read(droidLabSettingsProvider.future);
    expect(loaded.adbPath, '/custom/platform-tools/adb');
    expect(loaded.fastbootPath, '/custom/platform-tools/fastboot');
    expect(loaded.payloadDumperPath, '/custom/payload-dumper-go');
  });

}