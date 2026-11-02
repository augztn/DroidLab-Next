import 'package:droidlab_desktop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

void main() {
  testWidgets('collapses the navigation rail at laptop width', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
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

    expect(find.byTooltip('Dashboard'), findsOneWidget);
    expect(find.text('ANDROID ENGINEERING WORKSTATION'), findsNothing);
  });


  testWidgets('dashboard metric cards reflow to available workspace width', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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

    final backend = tester.getTopLeft(find.text('Backend'));
    final devices = tester.getTopLeft(find.text('Connected devices'));
    final desktop = tester.getTopLeft(find.text('Desktop'));
    expect(backend.dy, devices.dy);
    expect(backend.dy, desktop.dy);
    expect(backend.dx, lessThan(devices.dx));
    expect(devices.dx, lessThan(desktop.dx));
  });

  testWidgets('operation console can be collapsed and restored', (tester) async {
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

    expect(find.textContaining('Operation Console (Bounded'), findsOneWidget);
    expect(find.byTooltip('Hide console'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide console'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show console'), findsOneWidget);
    await tester.tap(find.byTooltip('Show console'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide console'), findsOneWidget);
  });
}
