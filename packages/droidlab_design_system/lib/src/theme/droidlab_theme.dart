import 'package:flutter/material.dart';

abstract final class DroidLabTokens {
  static const background = Color(0xFF10151C);
  static const sidebar = Color(0xFF171F29);
  static const surface = Color(0xFF171F29);
  static const panelAlt = Color(0xFF202C39);
  static const input = Color(0xFF0B1118);
  static const button = Color(0xFF243444);
  static const console = Color(0xFF080D13);
  static const border = Color(0xFF304253);
  static const primary = Color(0xFF59C7FF);
  static const secondary = Color(0xFF1679B8);
  static const text = Color(0xFFEDF4FB);
  static const muted = Color(0xFF9AABBA);
  static const success = Color(0xFF35C98A);
  static const warning = Color(0xFFF2B84B);
  static const error = Color(0xFFF87171);
}

abstract final class DroidLabTheme {
  static ThemeData light({String themeName = 'cyberpunk_glass'}) {
    final primary = switch (themeName) {
      'standard_dark' => const Color(0xFF2868D7),
      'oled_black' => const Color(0xFF386FDA),
      _ => const Color(0xFF1679B8),
    };
    const background = Color(0xFFF4F7FA);
    const sidebar = Color(0xFFE9EEF4);
    const surface = Color(0xFFFFFFFF);
    const panelAlt = Color(0xFFF1F4F8);
    const input = Color(0xFFFAFCFE);
    const button = Color(0xFFDCE7F2);
    const console = Color(0xFF101820);
    const border = Color(0xFFCBD5E1);
    const text = Color(0xFF17212B);
    const muted = Color(0xFF526171);

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    ).copyWith(
      primary: primary,
      secondary: primary,
      surface: surface,
      error: const Color(0xFFB42318),
      onSurface: text,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
      typography: Typography.material2021(platform: TargetPlatform.windows),
      listTileTheme: const ListTileThemeData(dense: true, minVerticalPadding: 6, horizontalTitleGap: 12),
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: button,
          foregroundColor: text,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: sidebar,
        foregroundColor: text,
        elevation: 0,
      ),
      extensions: const [
        DroidLabThemeSurfaces(console: console, panelAlt: panelAlt),
      ],
    );
  }

  static ThemeData dark({String themeName = 'cyberpunk_glass'}) {
    final colors = switch (themeName) {
      'standard_dark' => (
        background: const Color(0xFF111113),
        sidebar: const Color(0xFF19191D),
        surface: const Color(0xFF19191D),
        panelAlt: const Color(0xFF222228),
        input: const Color(0xFF101014),
        button: const Color(0xFF26262D),
        console: const Color(0xFF0B0B0E),
        border: const Color(0xFF303038),
        primary: const Color(0xFF4B8DFF),
        secondary: const Color(0xFF2868D7),
        text: const Color(0xFFF2F2F5),
        muted: const Color(0xFF9696A3),
      ),
      'oled_black' => (
        background: const Color(0xFF050506),
        sidebar: const Color(0xFF0E0E11),
        surface: const Color(0xFF0E0E11),
        panelAlt: const Color(0xFF19191D),
        input: const Color(0xFF08080A),
        button: const Color(0xFF1B1B20),
        console: const Color(0xFF030304),
        border: const Color(0xFF29292F),
        primary: const Color(0xFF78AAFF),
        secondary: const Color(0xFF386FDA),
        text: const Color(0xFFF5F5F7),
        muted: const Color(0xFF9696A3),
      ),
      _ => (
        background: const Color(0xFF10151C),
        sidebar: const Color(0xFF171F29),
        surface: const Color(0xFF171F29),
        panelAlt: const Color(0xFF202C39),
        input: const Color(0xFF0B1118),
        button: const Color(0xFF243444),
        console: const Color(0xFF080D13),
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
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
      typography: Typography.material2021(platform: TargetPlatform.windows),
      listTileTheme: const ListTileThemeData(dense: true, minVerticalPadding: 6, horizontalTitleGap: 12),
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
        isDense: true,
        filled: true,
        fillColor: colors.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.button,
          foregroundColor: colors.text,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.sidebar,
        foregroundColor: colors.text,
        elevation: 0,
      ),
      extensions: [
        DroidLabThemeSurfaces(console: colors.console, panelAlt: colors.panelAlt),
      ],
    );
  }
}

@immutable
class DroidLabThemeSurfaces extends ThemeExtension<DroidLabThemeSurfaces> {
  const DroidLabThemeSurfaces({required this.console, required this.panelAlt});
  final Color console;
  final Color panelAlt;

  @override
  DroidLabThemeSurfaces copyWith({Color? console, Color? panelAlt}) =>
      DroidLabThemeSurfaces(
        console: console ?? this.console,
        panelAlt: panelAlt ?? this.panelAlt,
      );

  @override
  DroidLabThemeSurfaces lerp(ThemeExtension<DroidLabThemeSurfaces>? other, double t) {
    if (other is! DroidLabThemeSurfaces) return this;
    return DroidLabThemeSurfaces(
      console: Color.lerp(console, other.console, t) ?? console,
      panelAlt: Color.lerp(panelAlt, other.panelAlt, t) ?? panelAlt,
    );
  }
}
