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

  testWidgets('workspace does not reserve space for the removed console', (tester) async {
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

    expect(find.text('Operation Console'), findsNothing);
    expect(find.byTooltip('Hide console'), findsNothing);
    expect(find.byTooltip('Show console'), findsNothing);
  });
}
