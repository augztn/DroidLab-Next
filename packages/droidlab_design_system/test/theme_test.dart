import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark theme uses Material 3 and expected semantic tokens', () {
    final theme = DroidLabTheme.dark();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, DroidLabTokens.primary);
    expect(theme.scaffoldBackgroundColor, DroidLabTokens.background);
  });
}
