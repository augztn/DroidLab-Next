import 'package:droidlab_desktop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapses the navigation rail at laptop width', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: DroidLabApp()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Dashboard'), findsOneWidget);
    expect(find.text('ANDROID ENGINEERING WORKSTATION'), findsNothing);
  });

  testWidgets('console can be hidden and restored', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: DroidLabApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hide console'));
    await tester.pumpAndSettle();
    expect(find.text('OPERATION CONSOLE'), findsNothing);

    await tester.tap(find.text('Show console'));
    await tester.pumpAndSettle();
    expect(find.text('OPERATION CONSOLE'), findsOneWidget);
  });
}
