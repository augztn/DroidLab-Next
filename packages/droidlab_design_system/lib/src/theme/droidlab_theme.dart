import 'package:flutter/material.dart';

abstract final class DroidLabTheme {
  static ThemeData dark({String themeName = 'cyberpunk_glass'}) {
    final colors = switch (themeName) {
      'standard_dark' => (
        background: const Color(0xFF111113),
        sidebar: const Color(0xFF19191D),
        surface: const Color(0xFF222228),
        elevated: const Color(0xFF2A2A32),
        border: const Color(0xFF303038),
        primary: const Color(0xFF4B8DFF),
        secondary: const Color(0xFF2868D7),
        text: const Color(0xFFF2F2F5),
        muted: const Color(0xFF9696A3),
      ),
      'oled_black' => (
        background: const Color(0xFF050506),
        sidebar: const Color(0xFF0E0E11),
        surface: const Color(0xFF19191D),
        elevated: const Color(0xFF202026),
        border: const Color(0xFF29292F),
        primary: const Color(0xFF78AAFF),
        secondary: const Color(0xFF386FDA),
        text: const Color(0xFFF5F5F7),
        muted: const Color(0xFF9696A3),
      ),
      _ => (
        background: const Color(0xFF10151C),
        sidebar: const Color(0xFF171F29),
        surface: const Color(0xFF202C39),
        elevated: const Color(0xFF263444),
        border: const Color(0xFF304253),
        primary: const Color(0xFF59C7FF),
        secondary: const Color(0xFF1679B8),
        text: const Color(0xFFEDF4FB),
        muted: const Color(0xFF9AABBA),
      ),
    };

    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: Brightness.dark,
      surface: colors.surface,
    ).copyWith(
      primary: colors.primary,
      secondary: colors.secondary,
      surface: colors.surface,
      error: const Color(0xFFF87171),
      onSurface: colors.text,
      onSurfaceVariant: colors.muted,
      outline: colors.border,
      outlineVariant: colors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.border,
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.sidebar,
        foregroundColor: colors.text,
        elevation: 0,
      ),
    );
  }
}
