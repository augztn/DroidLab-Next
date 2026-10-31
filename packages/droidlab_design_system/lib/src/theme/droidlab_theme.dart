import 'package:flutter/material.dart';

abstract final class DroidLabTokens {
  static const background = Color(0xFF0B0F14);
  static const sidebar = Color(0xFF111827);
  static const surface = Color(0xFF151D2B);
  static const elevatedSurface = Color(0xFF1B2638);
  static const border = Color(0xFF2A374A);
  static const primary = Color(0xFF3B82F6);
  static const secondary = Color(0xFF8B5CF6);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFF94A3B8);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
}

abstract final class DroidLabTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: DroidLabTokens.primary,
      brightness: Brightness.dark,
      surface: DroidLabTokens.surface,
    ).copyWith(
      primary: DroidLabTokens.primary,
      secondary: DroidLabTokens.secondary,
      surface: DroidLabTokens.surface,
      error: DroidLabTokens.error,
      onSurface: DroidLabTokens.text,
      onSurfaceVariant: DroidLabTokens.muted,
      outline: DroidLabTokens.border,
      outlineVariant: DroidLabTokens.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: DroidLabTokens.background,
      dividerColor: DroidLabTokens.border,
      cardTheme: CardTheme(
        color: DroidLabTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DroidLabTokens.radiusMedium),
          side: const BorderSide(color: DroidLabTokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DroidLabTokens.elevatedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DroidLabTokens.radiusSmall),
          borderSide: const BorderSide(color: DroidLabTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DroidLabTokens.radiusSmall),
          borderSide: const BorderSide(color: DroidLabTokens.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: DroidLabTokens.sidebar,
        foregroundColor: DroidLabTokens.text,
        elevation: 0,
      ),
    );
  }
}
