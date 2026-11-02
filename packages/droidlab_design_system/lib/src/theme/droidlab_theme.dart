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
    return _build(
      brightness: Brightness.light, primary: primary, secondary: primary,
      background: const Color(0xFFF4F7FA), sidebar: const Color(0xFFE9EEF4),
      surface: Colors.white, panelAlt: const Color(0xFFF1F4F8),
      input: const Color(0xFFFAFCFE), button: const Color(0xFFDCE7F2),
      console: const Color(0xFF101820), border: const Color(0xFFCBD5E1),
      text: const Color(0xFF17212B), muted: const Color(0xFF526171),
      error: const Color(0xFFB42318),
    );
  }

  static ThemeData dark({String themeName = 'cyberpunk_glass'}) {
    final colors = switch (themeName) {
      'standard_dark' => (
        background: const Color(0xFF111113), sidebar: const Color(0xFF19191D),
        surface: const Color(0xFF19191D), panelAlt: const Color(0xFF222228),
        input: const Color(0xFF101014), button: const Color(0xFF26262D),
        console: const Color(0xFF0B0B0E), border: const Color(0xFF303038),
        primary: const Color(0xFF4B8DFF), secondary: const Color(0xFF2868D7),
        text: const Color(0xFFF2F2F5), muted: const Color(0xFF9696A3),
      ),
      'oled_black' => (
        background: const Color(0xFF050506), sidebar: const Color(0xFF0E0E11),
        surface: const Color(0xFF0E0E11), panelAlt: const Color(0xFF19191D),
        input: const Color(0xFF08080A), button: const Color(0xFF1B1B20),
        console: const Color(0xFF030304), border: const Color(0xFF29292F),
        primary: const Color(0xFF78AAFF), secondary: const Color(0xFF386FDA),
        text: const Color(0xFFF5F5F7), muted: const Color(0xFF9696A3),
      ),
      _ => (
        background: const Color(0xFF10151C), sidebar: const Color(0xFF171F29),
        surface: const Color(0xFF171F29), panelAlt: const Color(0xFF202C39),
        input: const Color(0xFF0B1118), button: const Color(0xFF243444),
        console: const Color(0xFF080D13), border: const Color(0xFF304253),
        primary: const Color(0xFF59C7FF), secondary: const Color(0xFF1679B8),
        text: const Color(0xFFEDF4FB), muted: const Color(0xFF9AABBA),
      ),
    };
    return _build(
      brightness: Brightness.dark, primary: colors.primary,
      secondary: colors.secondary, background: colors.background,
      sidebar: colors.sidebar, surface: colors.surface,
      panelAlt: colors.panelAlt, input: colors.input, button: colors.button,
      console: colors.console, border: colors.border, text: colors.text,
      muted: colors.muted, error: const Color(0xFFF87171),
    );
  }

  static ThemeData _build({
    required Brightness brightness, required Color primary,
    required Color secondary, required Color background,
    required Color sidebar, required Color surface,
    required Color panelAlt, required Color input, required Color button,
    required Color console, required Color border, required Color text,
    required Color muted, required Color error,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary, brightness: brightness, surface: surface,
    ).copyWith(
      primary: primary, secondary: secondary, surface: surface,
      error: error, onSurface: text, onSurfaceVariant: muted,
      outline: border, outlineVariant: border,
    );
    final base = Typography.material2021(platform: defaultTargetPlatform);
    final textTheme = base.copyWith(
      displayLarge: base.displayLarge?.copyWith(color: text, letterSpacing: -1.2),
      displayMedium: base.displayMedium?.copyWith(color: text, letterSpacing: -0.9),
      displaySmall: base.displaySmall?.copyWith(color: text, letterSpacing: -0.7),
      headlineLarge: base.headlineLarge?.copyWith(color: text, fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: base.headlineMedium?.copyWith(color: text, fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineSmall: base.headlineSmall?.copyWith(color: text, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: base.titleLarge?.copyWith(color: text, fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(color: text, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(color: text, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(color: text, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(color: text, height: 1.4),
      bodySmall: base.bodySmall?.copyWith(color: muted, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(color: text, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600, letterSpacing: 0.15),
      labelSmall: base.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w700, letterSpacing: 0.45),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
    return ThemeData(
      useMaterial3: true, textTheme: textTheme,
      visualDensity: VisualDensity.standard, colorScheme: scheme,
      scaffoldBackgroundColor: background, dividerColor: border,
      listTileTheme: ListTileThemeData(
        dense: true, minVerticalPadding: 7, horizontalTitleGap: 12,
        selectedColor: primary, selectedTileColor: primary.withOpacity(0.12),
        iconColor: muted,
      ),
      cardTheme: CardThemeData(
        color: surface, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true, filled: true, fillColor: input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: muted.withOpacity(0.85), fontSize: 14),
        labelStyle: TextStyle(color: muted, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: primary, width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: error, width: 1.4)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor: button, foregroundColor: text, minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: buttonShape, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      )),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: buttonShape, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: primary, minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        side: BorderSide(color: border), shape: buttonShape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: primary, minimumSize: const Size(0, 38),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      )),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
        foregroundColor: muted, minimumSize: const Size(38, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      )),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: panelAlt, borderRadius: BorderRadius.circular(7), border: Border.all(color: border)),
        textStyle: TextStyle(color: text, fontSize: 12),
      ),
      appBarTheme: AppBarTheme(backgroundColor: sidebar, foregroundColor: text, elevation: 0),
      extensions: [DroidLabThemeSurfaces(console: console, panelAlt: panelAlt)],
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
      DroidLabThemeSurfaces(console: console ?? this.console, panelAlt: panelAlt ?? this.panelAlt);

  @override
  DroidLabThemeSurfaces lerp(ThemeExtension<DroidLabThemeSurfaces>? other, double t) {
    if (other is! DroidLabThemeSurfaces) return this;
    return DroidLabThemeSurfaces(
      console: Color.lerp(console, other.console, t) ?? console,
      panelAlt: Color.lerp(panelAlt, other.panelAlt, t) ?? panelAlt,
    );
  }
}
