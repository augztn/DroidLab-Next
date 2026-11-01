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
  String? recoveryNotice;
  bool _unreadableConfigPreserved = false;

  static File _defaultFile() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ?? Directory.current.path;
    return File('$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}config.json');
  }

  Future<DroidLabSettings> load() async {
    recoveryNotice = null;
    _unreadableConfigPreserved = false;
    try {
      final value = jsonDecode(await _file.readAsString());
      if (value is Map<String, dynamic>) return DroidLabSettings.fromJson(value);
      if (value is Map) return DroidLabSettings.fromJson(value.cast<String, dynamic>());
      await _preserveCorruptConfig('The settings file did not contain a JSON object.');
    } on FileSystemException catch (error) {
      // First launch is normal. If a file exists but cannot be read, preserve
      // it so a later save cannot silently discard potentially valid settings.
      if (await _file.exists()) {
        await _preserveCorruptConfig('The settings file could not be read: ${error.message}.');
      }
    } on FormatException catch (error) {
      // Preserve malformed and unsupported future schemas instead of silently
      // replacing the only copy when the user next saves settings.
      await _preserveCorruptConfig(error.message);
    }
    return DroidLabSettings(
      pythonPath: Platform.environment['DROIDLAB_PYTHON'] ?? '',
      backendPath: Platform.environment['DROIDLAB_BACKEND_SCRIPT'] ?? '',
      adbPath: Platform.environment['DROIDLAB_ADB_PATH'] ?? '',
      fastbootPath: Platform.environment['DROIDLAB_FASTBOOT_PATH'] ?? '',
      payloadDumperPath: Platform.environment['DROIDLAB_PAYLOAD_DUMPER_GO_PATH'] ?? '',
    );
  }

  Future<void> _preserveCorruptConfig(String reason) async {
    try {
      if (!await _file.exists()) return;
      final preserved = File(
        '${_file.path}.corrupt.${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      await _file.rename(preserved.path);
      _unreadableConfigPreserved = true;
      recoveryNotice = '${reason} The original file was preserved at ${preserved.path}. Defaults are active; review the recovered file before saving new settings.';
    } on FileSystemException catch (error) {
      _unreadableConfigPreserved = false;
      recoveryNotice = 'The settings file could not be read or preserved. No replacement has been written. Details: ${error.message}';
    }
  }

  Future<void> save(DroidLabSettings settings) async {
    if (recoveryNotice != null &&
        !_unreadableConfigPreserved &&
        await _file.exists()) {
      throw FileSystemException(
        'Refusing to overwrite an unreadable settings file that could not be preserved.',
        _file.path,
      );
    }
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
    try {
      await ref.read(droidLabSettingsStoreProvider).save(settings);
      state = AsyncData(settings);
    } catch (error, stack) {
      state = previous;
      Error.throwWithStackTrace(error, stack);
    }
  }
}