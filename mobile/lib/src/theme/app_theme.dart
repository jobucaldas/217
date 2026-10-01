import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 217 visual system — calm forest intake tracker, not a generic Material seed.
abstract final class App217Colors {
  static const ink = Color(0xFF122018);
  static const inkMuted = Color(0xFF5C7264);
  static const forest = Color(0xFF1F6F5B);
  static const forestDeep = Color(0xFF134A3D);
  static const moss = Color(0xFFD8EDE4);
  static const canvas = Color(0xFFF2F6F3);
  static const surface = Color(0xFFFFFCF7);
  static const line = Color(0xFFCFDDD4);
  static const taken = Color(0xFF1B7A4A);
  static const missed = Color(0xFFB42318);
  static const missedSoft = Color(0xFFFCE8E6);

  /// Status / cell fills — lighter in dark mode so labels stay readable.
  static const takenDark = Color(0xFF3DDC8A);
  static const missedDark = Color(0xFFFF8A80);
  static const takenFillDark = Color(0xFF145C38);
  static const missedFillDark = Color(0xFF8B1E18);

  static Color statusTaken(Brightness b) =>
      b == Brightness.dark ? takenDark : taken;

  static Color statusMissed(Brightness b) =>
      b == Brightness.dark ? missedDark : missed;

  static Color cellTaken(Brightness b) =>
      b == Brightness.dark ? takenFillDark : taken;

  static Color cellMissed(Brightness b) =>
      b == Brightness.dark ? missedFillDark : missed;
}

/// Colors only — safe for unit tests (no Google Fonts / binding).
ColorScheme buildApp217ColorScheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ColorScheme(
    brightness: brightness,
    primary: isDark ? const Color(0xFF7BC4AE) : App217Colors.forest,
    onPrimary: isDark ? App217Colors.ink : Colors.white,
    primaryContainer: isDark ? App217Colors.forestDeep : App217Colors.moss,
    onPrimaryContainer: isDark ? App217Colors.moss : App217Colors.forestDeep,
    secondary: isDark ? const Color(0xFFC5D4CB) : App217Colors.ink,
    onSecondary: isDark ? App217Colors.ink : Colors.white,
    secondaryContainer: isDark ? const Color(0xFF24352C) : const Color(0xFFE4EEE8),
    onSecondaryContainer: isDark ? App217Colors.moss : App217Colors.ink,
    tertiary: App217Colors.forestDeep,
    onTertiary: Colors.white,
    error: App217Colors.missed,
    onError: Colors.white,
    errorContainer: App217Colors.missedSoft,
    onErrorContainer: App217Colors.missed,
    surface: isDark ? const Color(0xFF101916) : App217Colors.surface,
    onSurface: isDark ? const Color(0xFFE7F0EA) : App217Colors.ink,
    onSurfaceVariant: isDark ? const Color(0xFFA8BDB2) : App217Colors.inkMuted,
    outline: isDark ? const Color(0xFF3D5247) : App217Colors.line,
    outlineVariant: isDark ? const Color(0xFF24352C) : App217Colors.moss,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: App217Colors.ink,
    onInverseSurface: App217Colors.canvas,
    inversePrimary: App217Colors.moss,
    surfaceTint: App217Colors.forest,
  );
}

Color scaffoldBackgroundFor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF0C1411)
        : App217Colors.canvas;

ThemeData buildApp217Theme({required Brightness brightness}) {
  final scheme = buildApp217ColorScheme(brightness);

  final display = GoogleFonts.frauncesTextTheme();
  final body = GoogleFonts.sourceSans3TextTheme();
  final textTheme = body.copyWith(
    displayLarge: display.displayLarge?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.2,
      fontSize: 56,
      height: 1.0,
    ),
    headlineMedium: display.headlineMedium?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 28,
      height: 1.15,
    ),
    titleLarge: body.titleLarge?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: body.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
      fontSize: 17,
    ),
    bodyMedium: body.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: scaffoldBackgroundFor(brightness),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.headlineMedium?.copyWith(fontSize: 24),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
      ),
    ),
  );
}
