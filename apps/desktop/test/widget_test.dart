import 'package:droidlab_desktop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

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
    expect(find.text('Operation History'), findsOneWidget);
    expect(find.text('OPERATION CONSOLE'), findsOneWidget);
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

    expect(find.text('Destructive actions require fresh target validation and an explicit confirmation.'), findsOneWidget);
    expect(find.text('Detected Fastboot devices'), findsOneWidget);
    expect(find.text('Flash image'), findsOneWidget);
  });
  testWidgets('Settings exposes persistent themes and executable paths', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Python executable'), findsOneWidget);
    expect(find.text('Backend script'), findsOneWidget);
    expect(find.text('ADB executable'), findsOneWidget);
    expect(find.text('Fastboot executable'), findsOneWidget);
    expect(find.text('Payload dumper'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
  });

}
