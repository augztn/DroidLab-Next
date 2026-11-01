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

  test('preserves malformed config and exposes a recovery notice', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-corrupt-settings-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File(temporary.path + '/config.json');
    await file.writeAsString('{ invalid json');
    final store = DroidLabSettingsStore(file: file);

    final settings = await store.load();

    expect(settings.theme, 'cyberpunk_glass');
    expect(store.recoveryNotice, contains('preserved'));
    expect(await file.exists(), isFalse);
    final recovered = temporary.listSync().whereType<File>().single;
    expect(recovered.path, contains('.corrupt.'));
    expect(await recovered.readAsString(), '{ invalid json');
  });

  test('preserves unsupported future schema without overwriting it', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-future-settings-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File(temporary.path + '/config.json');
    await file.writeAsString('{"schema_version":99,"theme":"oled_black"}');
    final store = DroidLabSettingsStore(file: file);

    await store.load();

    expect(store.recoveryNotice, contains('preserved'));
    expect(await file.exists(), isFalse);
    expect(temporary.listSync().whereType<File>(), hasLength(1));
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
  test('saved tool paths remain in config for backend per-command resolution', () async {
    final temporary = await Directory.systemTemp.createTemp('droidlab-tool-env-');
    addTearDown(() => temporary.delete(recursive: true));
    final config = File(temporary.path + '/DroidLab/config.json');
    final store = DroidLabSettingsStore(file: config);
    const value = DroidLabSettings(
      adbPath: '/custom/platform-tools/adb',
      fastbootPath: '/custom/platform-tools/fastboot',
      payloadDumperPath: '/custom/payload-dumper-go',
    );

    await store.save(value);

    // The Python backend reads this shared legacy config on every tool lookup.
    // The long-lived Dart process must not freeze these values into child env.
    final persisted = await config.readAsString();
    expect(persisted, contains('"adb_path": "/custom/platform-tools/adb"'));
    expect(persisted, contains('"fastboot_path": "/custom/platform-tools/fastboot"'));
    expect(persisted, contains('"payload_dumper_path": "/custom/payload-dumper-go"'));
  });

}