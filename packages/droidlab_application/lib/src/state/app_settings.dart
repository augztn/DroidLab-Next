import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class DroidLabSettings {
  const DroidLabSettings({
    this.theme = 'cyberpunk_glass',
    this.pythonPath = '',
    this.backendPath = '',
    this.adbPath = '',
    this.fastbootPath = '',
    this.payloadDumperPath = '',
  });

  final String theme;
  final String pythonPath;
  final String backendPath;
  final String adbPath;
  final String fastbootPath;
  final String payloadDumperPath;

  DroidLabSettings copyWith({
    String? theme, String? pythonPath, String? backendPath,
    String? adbPath, String? fastbootPath, String? payloadDumperPath,
  }) => DroidLabSettings(
        theme: theme ?? this.theme,
        pythonPath: pythonPath ?? this.pythonPath,
        backendPath: backendPath ?? this.backendPath,
        adbPath: adbPath ?? this.adbPath,
        fastbootPath: fastbootPath ?? this.fastbootPath,
        payloadDumperPath: payloadDumperPath ?? this.payloadDumperPath,
      );

  factory DroidLabSettings.fromJson(Map<String, dynamic> json) {
    // Configurations written before schema versioning are version 0.
    // Keep reading them indefinitely so upgrades never discard user paths.
    final version = json['schema_version'] ?? 0;
    if (version != 0 && version != 1) {
      throw FormatException('Unsupported settings schema version: $version');
    }
    return DroidLabSettings(
        theme: _validTheme(json['theme']),
        pythonPath: _string(json['python_path'] ?? json['python']),
        backendPath: _string(json['backend_path'] ?? json['backend_script']),
        adbPath: _string(json['adb_path'] ?? json['adb']),
        fastbootPath: _string(json['fastboot_path'] ?? json['fastboot']),
        payloadDumperPath: _string(json['payload_dumper_path'] ?? json['payload_dumper_go']),
      );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'theme': theme, 'python_path': pythonPath, 'backend_path': backendPath,
        'adb_path': adbPath, 'fastboot_path': fastbootPath,
        'payload_dumper_path': payloadDumperPath,
      };

  static String _string(Object? value) => value is String ? value.trim() : '';
  static String _validTheme(Object? value) =>
      const {'cyberpunk_glass', 'standard_dark', 'oled_black'}.contains(value)
          ? value as String : 'cyberpunk_glass';
}

class DroidLabSettingsStore {
  DroidLabSettingsStore({File? file}) : _file = file ?? _defaultFile();
  final File _file;

  static File _defaultFile() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ?? Directory.current.path;
    return File('$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}config.json');
  }

  Future<DroidLabSettings> load() async {
    try {
      final value = jsonDecode(await _file.readAsString());
      if (value is Map<String, dynamic>) return DroidLabSettings.fromJson(value);
      if (value is Map) return DroidLabSettings.fromJson(value.cast<String, dynamic>());
    } on FileSystemException {
      // First launch or unavailable legacy config: use environment defaults.
    } on FormatException {
      // A malformed or unsupported config must not prevent app startup.
    }
    return DroidLabSettings(
      pythonPath: Platform.environment['DROIDLAB_PYTHON'] ?? '',
      backendPath: Platform.environment['DROIDLAB_BACKEND_SCRIPT'] ?? '',
      adbPath: Platform.environment['DROIDLAB_ADB_PATH'] ?? '',
      fastbootPath: Platform.environment['DROIDLAB_FASTBOOT_PATH'] ?? '',
      payloadDumperPath: Platform.environment['DROIDLAB_PAYLOAD_DUMPER_GO_PATH'] ?? '',
    );
  }

  Future<void> save(DroidLabSettings settings) async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    final backup = File('${_file.path}.bak');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );

    var movedOriginal = false;
    try {
      if (await backup.exists()) await backup.delete();
      if (await _file.exists()) {
        await _file.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(_file.path);
      if (movedOriginal && await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (movedOriginal && !await _file.exists() && await backup.exists()) {
        await backup.rename(_file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String get path => _file.path;
}

final droidLabSettingsStoreProvider = Provider<DroidLabSettingsStore>(
  (ref) => DroidLabSettingsStore(),
);

final droidLabSettingsProvider =
    AsyncNotifierProvider<DroidLabSettingsController, DroidLabSettings>(
  DroidLabSettingsController.new,
);

class DroidLabSettingsController extends AsyncNotifier<DroidLabSettings> {
  @override
  Future<DroidLabSettings> build() => ref.read(droidLabSettingsStoreProvider).load();

  Future<void> saveSettings(DroidLabSettings settings) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await ref.read(droidLabSettingsStoreProvider).save(settings);
      state = AsyncData(settings);
    } catch (error, stack) {
      state = previous;
      Error.throwWithStackTrace(error, stack);
    }
  }
}