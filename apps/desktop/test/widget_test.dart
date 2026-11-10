import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_desktop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _TestSettingsController extends DroidLabSettingsController {
  @override
  Future<DroidLabSettings> build() async => const DroidLabSettings();
}

void main() {
  testWidgets('renders desktop shell and feature navigation', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testBackendOverrides(),
        child: const DroidLabApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DroidLab'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Device Manager'), findsOneWidget);
    expect(find.text('Firmware & Payload'), findsOneWidget);
    expect(find.text('ADB Toolkit'), findsOneWidget);
    expect(find.text('Fastboot Toolkit'), findsOneWidget);
    expect(find.text('Logs & Diagnostics'), findsOneWidget);
    expect(find.textContaining('Operation Console (Bounded'), findsOneWidget);
  });

  testWidgets('sidebar navigation opens the Fastboot workflow', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testBackendOverrides(),
        child: const DroidLabApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fastboot Toolkit'));
    await tester.pumpAndSettle();

    expect(find.text('Fastboot Toolkit & Guarded Flashing'), findsOneWidget);
    expect(find.text('Guarded Partition Flash (fastboot.flash)'), findsOneWidget);
    expect(find.text('Preview & Confirm Flash'), findsOneWidget);
    expect(find.text('A/B Active Slot Switcher (fastboot.set_active)'), findsOneWidget);
  });

  testWidgets('Settings exposes persistent themes and executable paths',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testBackendOverrides(),
          droidLabSettingsProvider.overrideWith(_TestSettingsController.new),
        ],
        child: const DroidLabApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('General'), findsWidgets);
    expect(find.text('Interface'), findsOneWidget);
    expect(find.text('Device Tools'), findsOneWidget);

    // Settings are intentionally split into focused sections. Verify the
    // appearance controls in Interface rather than assuming they are all
    // mounted on the initial General section.
    await tester.tap(find.text('Interface').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance & Theme Identity'), findsOneWidget);
    expect(find.text('Cyberpunk Glass'), findsOneWidget);
    expect(find.text('Standard Dark'), findsOneWidget);
    expect(find.text('OLED Black'), findsOneWidget);
    expect(find.text('Switch to Light Surface'), findsOneWidget);

    await tester.tap(find.text('Device Tools').last);
    await tester.pumpAndSettle();
    expect(find.text('Python executable'), findsOneWidget);
    expect(find.text('Backend script'), findsOneWidget);
    expect(find.text('ADB executable'), findsOneWidget);
    expect(find.text('Fastboot executable'), findsOneWidget);
    expect(find.text('Payload dumper'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
  });
}
