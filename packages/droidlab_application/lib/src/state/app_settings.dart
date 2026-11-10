import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class DroidLabSettings {
  const DroidLabSettings({
    this.theme = 'cyberpunk_glass',
    this.themeMode = 'dark',
    this.pythonPath = '',
    this.backendPath = '',
    this.adbPath = '',
    this.fastbootPath = '',
    this.payloadDumperPath = '',
    this.autoSwitchDeviceToolPrompts = true,
  });

  final String theme;
  final String themeMode;
  final String pythonPath;
  final String backendPath;
  final String adbPath;
  final String fastbootPath;
  final String payloadDumperPath;
  final bool autoSwitchDeviceToolPrompts;

  DroidLabSettings copyWith({
    String? theme, String? themeMode, String? pythonPath, String? backendPath,
    String? adbPath, String? fastbootPath, String? payloadDumperPath,
    bool? autoSwitchDeviceToolPrompts,
  }) => DroidLabSettings(
        theme: theme ?? this.theme,
        themeMode: themeMode ?? this.themeMode,
        pythonPath: pythonPath ?? this.pythonPath,
        backendPath: backendPath ?? this.backendPath,
        adbPath: adbPath ?? this.adbPath,
        fastbootPath: fastbootPath ?? this.fastbootPath,
        payloadDumperPath: payloadDumperPath ?? this.payloadDumperPath,
        autoSwitchDeviceToolPrompts: autoSwitchDeviceToolPrompts ?? this.autoSwitchDeviceToolPrompts,
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
        themeMode: _validThemeMode(json['theme_mode']),
        pythonPath: _string(json['python_path'] ?? json['python']),
        backendPath: _string(json['backend_path'] ?? json['backend_script']),
        adbPath: _string(json['adb_path'] ?? json['adb']),
        fastbootPath: _string(json['fastboot_path'] ?? json['fastboot']),
        payloadDumperPath: _string(json['payload_dumper_path'] ?? json['payload_dumper_go']),
        autoSwitchDeviceToolPrompts: json['auto_switch_device_tool_prompts'] is bool
            ? json['auto_switch_device_tool_prompts'] as bool
            : true,
      );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'theme': theme, 'theme_mode': themeMode, 'python_path': pythonPath, 'backend_path': backendPath,
        'adb_path': adbPath, 'fastboot_path': fastbootPath,
        'payload_dumper_path': payloadDumperPath,
        'auto_switch_device_tool_prompts': autoSwitchDeviceToolPrompts,
      };

  static String _string(Object? value) => value is String ? value.trim() : '';
  static String _validThemeMode(Object? value) =>
      const {'light', 'dark', 'system'}.contains(value) ? value as String : 'dark';
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
    final backup = File('${_file.path}.bak');

    if (!await _file.exists()) {
      return await _restoreBackup(backup) ?? _defaultSettings();
    }

    try {
      return _decodeSettings(await _file.readAsString());
    } on FileSystemException catch (error) {
      if (await _file.exists()) {
        await _preserveCorruptConfig('The settings file could not be read: ${error.message}.');
      }
    } on FormatException catch (error) {
      // Preserve malformed and unsupported future schemas before considering
      // the backup, so the original data remains available for inspection.
      await _preserveCorruptConfig(error.message);
    }

    // Only restore when the original primary file was successfully preserved.
    if (!await _file.exists() && await backup.exists()) {
      final recovered = await _restoreBackup(
        backup,
        previousNotice: recoveryNotice,
      );
      if (recovered != null) return recovered;
    }
    if (recoveryNotice != null) {
      recoveryNotice =
          '$recoveryNotice Defaults are active; review the preserved files before saving new settings.';
    }
    return _defaultSettings();
  }

  DroidLabSettings _decodeSettings(String contents) {
    final value = jsonDecode(contents);
    if (value is Map<String, dynamic>) return DroidLabSettings.fromJson(value);
    if (value is Map) return DroidLabSettings.fromJson(value.cast<String, dynamic>());
    throw const FormatException('The settings file did not contain a JSON object.');
  }

  Future<DroidLabSettings?> _restoreBackup(
    File backup, {
    String? previousNotice,
  }) async {
    if (!await backup.exists()) return null;
    try {
      final settings = _decodeSettings(await backup.readAsString());
      if (await _file.exists()) {
        throw FileSystemException(
          'The primary settings file could not be preserved; refusing to replace it.',
          _file.path,
        );
      }
      await backup.rename(_file.path);
      _unreadableConfigPreserved = true;
      recoveryNotice = [
        if (previousNotice != null) previousNotice,
        'Settings were restored from the backup after an interrupted or corrupt save.',
      ].join(' ');
      return settings;
    } on FormatException catch (error) {
      _unreadableConfigPreserved = false;
      recoveryNotice = [
        if (previousNotice != null) previousNotice,
        'The settings backup is invalid and was preserved at ${backup.path}: ${error.message}',
      ].join(' ');
    } on FileSystemException catch (error) {
      _unreadableConfigPreserved = false;
      recoveryNotice = [
        if (previousNotice != null) previousNotice,
        'The settings backup could not be restored: ${error.message}',
      ].join(' ');
    }
    return null;
  }

  DroidLabSettings _defaultSettings() => DroidLabSettings(
        pythonPath: Platform.environment['DROIDLAB_PYTHON'] ?? '',
        backendPath: Platform.environment['DROIDLAB_BACKEND_SCRIPT'] ?? '',
        adbPath: Platform.environment['DROIDLAB_ADB_PATH'] ?? '',
        fastbootPath: Platform.environment['DROIDLAB_FASTBOOT_PATH'] ?? '',
        payloadDumperPath: Platform.environment['DROIDLAB_PAYLOAD_DUMPER_GO_PATH'] ?? '',
      );

  Future<void> _preserveCorruptConfig(String reason) async {
    try {
      if (!await _file.exists()) return;
      final preserved = File(
        '${_file.path}.corrupt.${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      await _file.rename(preserved.path);
      _unreadableConfigPreserved = true;
      recoveryNotice = '${reason} The original file was preserved at ${preserved.path}.';
    } on FileSystemException catch (error) {
      _unreadableConfigPreserved = false;
      recoveryNotice = 'The settings file could not be read or preserved. No replacement has been written. Details: ${error.message}';
    }
  }

  Future<void> save(DroidLabSettings settings) async {
    if (recoveryNotice != null &&
        !_unreadableConfigPreserved &&
        (await _file.exists() || await File('${_file.path}.bak').exists())) {
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