import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:droidlab_backend_bridge/droidlab_backend_bridge.dart';
import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../diagnostics/diagnostic_redactor.dart';
import 'fastboot_command.dart';
import 'debloat_action.dart';
import '../state/app_settings.dart';
import '../state/backend_providers.dart';
import '../state/operation_history.dart';

part 'feature_dashboard.part.dart';
part 'feature_devices.part.dart';
part 'feature_debloater.part.dart';
part 'feature_app_manager.part.dart';
part 'feature_adb.part.dart';
part 'feature_fastboot.part.dart';
part 'feature_payload.part.dart';
part 'feature_logs.part.dart';
part 'feature_about.part.dart';
part 'feature_settings.part.dart';
part 'feature_shared.part.dart';

Future<bool> _waitForDeviceTransport({
  required BuildContext context,
  required WidgetRef ref,
  required String serial,
  required String transport,
  String? fastbootMode,
}) async {
  // USB disconnect/re-enumeration is asynchronous after reboot. Poll a bounded
  // number of times and only navigate once the same serial is visible again
  // on the expected transport.
  for (var attempt = 0; attempt < 10; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    if (!context.mounted) return false;
    ref.invalidate(deviceListProvider);
    try {
      final pendingDevices = ref.read(deviceListProvider.future);
      final data = await pendingDevices;
      if (!context.mounted) return false;
      final devices = (data['devices'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      if (devices.any((device) =>
          device['serial'] == serial &&
          device['transport'] == transport &&
          (fastbootMode == null || device['mode'] == fastbootMode))) {
        return true;
      }
    } catch (_) {
      if (!context.mounted) return false;
      // The device may be temporarily absent while USB re-enumerates.
    }
  }
  return false;
}
