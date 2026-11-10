import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme adapts shared surfaces and preserves the selected accent', () {
    final theme = DroidLabTheme.light();
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, const Color(0xFF7054E8));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F7FA));
    expect(theme.cardTheme.color, Colors.white);
  });

  test('all dark surfaces stay synchronized with the legacy token palettes', () {
    const palettes = <String, Map<String, Color>>{
      'cyberpunk_glass': {
        'bg': Color(0xFF121026),
        'panel': Color(0xFF1D1A38),
        'panel_alt': Color(0xFF262247),
        'border': Color(0xFF39345B),
        'text': Color(0xFFF2F0FF),
        'muted': Color(0xFFAAA4C5),
        'input': Color(0xFF100F20),
        'accent': Color(0xFF9A82FF),
        'accent2': Color(0xFF1679B8),
        'console': Color(0xFF0C0B19),
      },
      'standard_dark': {
        'bg': Color(0xFF111113),
        'panel': Color(0xFF19191D),
        'panel_alt': Color(0xFF222228),
        'border': Color(0xFF303038),
        'text': Color(0xFFF2F2F5),
        'muted': Color(0xFF9696A3),
        'input': Color(0xFF101014),
        'accent': Color(0xFF4B8DFF),
        'accent2': Color(0xFF2868D7),
        'console': Color(0xFF0B0B0E),
      },
      'oled_black': {
        'bg': Color(0xFF050506),
        'panel': Color(0xFF0E0E11),
        'panel_alt': Color(0xFF19191D),
        'border': Color(0xFF29292F),
        'text': Color(0xFFF5F5F7),
        'muted': Color(0xFF9696A3),
        'input': Color(0xFF08080A),
        'accent': Color(0xFF78AAFF),
        'accent2': Color(0xFF386FDA),
        'console': Color(0xFF030304),
      },
    };
    for (final entry in palettes.entries) {
      final theme = DroidLabTheme.dark(themeName: entry.key);
      final tokens = entry.value;
      final surfaces = theme.extension<DroidLabThemeSurfaces>()!;
      expect(theme.scaffoldBackgroundColor, tokens['bg'], reason: entry.key);
      expect(theme.colorScheme.surface, tokens['panel'], reason: entry.key);
      expect(theme.dividerColor, tokens['border'], reason: entry.key);
      expect(theme.colorScheme.onSurface, tokens['text'], reason: entry.key);
      expect(theme.colorScheme.onSurfaceVariant, tokens['muted'], reason: entry.key);
      expect(theme.inputDecorationTheme.fillColor, tokens['input'], reason: entry.key);
      expect(theme.colorScheme.primary, tokens['accent'], reason: entry.key);
      expect(theme.colorScheme.secondary, tokens['accent2'], reason: entry.key);
      expect(surfaces.console, tokens['console'], reason: entry.key);
      expect(surfaces.panelAlt, tokens['panel_alt'], reason: entry.key);
    }
  });

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
