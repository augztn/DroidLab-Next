import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default dark theme uses the legacy cyberpunk glass palette', () {
    final theme = DroidLabTheme.dark();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF59C7FF));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF10151C));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFF0B1118));
  });

  test('standard dark theme uses the legacy charcoal palette', () {
    final theme = DroidLabTheme.dark(themeName: 'standard_dark');
    expect(theme.scaffoldBackgroundColor, const Color(0xFF111113));
    expect(theme.colorScheme.primary, const Color(0xFF4B8DFF));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFF101014));
  });

  test('OLED theme uses the legacy true-black palette', () {
    final theme = DroidLabTheme.dark(themeName: 'oled_black');
    expect(theme.scaffoldBackgroundColor, const Color(0xFF050506));
    expect(theme.colorScheme.primary, const Color(0xFF78AAFF));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFF08080A));
  });
}
