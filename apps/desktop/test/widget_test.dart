import 'package:droidlab_desktop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders desktop shell and feature navigation', (tester) async {
    await tester.view.setPhysicalSize(const Size(1440, 1000));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: DroidLabApp()));
    await tester.pumpAndSettle();

    expect(find.text('DroidLab'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Device Manager'), findsOneWidget);
    expect(find.text('Firmware Explorer'), findsOneWidget);
    expect(find.text('Payload Extractor'), findsOneWidget);
    expect(find.text('ADB Toolkit'), findsOneWidget);
    expect(find.text('Fastboot Toolkit'), findsOneWidget);
    expect(find.text('Logs & Diagnostics'), findsOneWidget);
    expect(find.text('Operation History'), findsOneWidget);
    expect(find.text('No device'), findsOneWidget);
    expect(find.text('OPERATION CONSOLE'), findsOneWidget);
  });

  testWidgets('sidebar navigation opens the Fastboot workflow', (tester) async {
    await tester.view.setPhysicalSize(const Size(1440, 1000));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: DroidLabApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fastboot Toolkit'));
    await tester.pumpAndSettle();

    expect(find.text('Destructive actions require fresh target validation and an explicit confirmation.'), findsOneWidget);
    expect(find.text('Fastboot serial'), findsOneWidget);
    expect(find.text('Flash image'), findsOneWidget);
  });
}
