import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

export 'palette.dart';

/// Status helpers used by calendar chrome (palette-aware).
abstract final class App217Colors {
  static Color statusTaken(Brightness b, [AppPalette palette = AppPalette.azure]) =>
      PaletteColors.resolve(palette, b).taken;

  static Color statusMissed(Brightness b, [AppPalette palette = AppPalette.azure]) =>
      PaletteColors.resolve(palette, b).missed;

  static Color cellTaken(Brightness b, [AppPalette palette = AppPalette.azure]) =>
      PaletteColors.resolve(palette, b).takenFill;

  static Color cellMissed(Brightness b, [AppPalette palette = AppPalette.azure]) =>
      PaletteColors.resolve(palette, b).missedFill;

  static Color onFilledCell(Brightness b, [AppPalette palette = AppPalette.azure]) =>
      PaletteColors.resolve(palette, b).onFilledCell;
}

/// Colors only — safe for unit tests (no Google Fonts / binding).
ColorScheme buildApp217ColorScheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.azure,
}) {
  final c = PaletteColors.resolve(palette, brightness);
  return ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.primary,
    onTertiary: c.onPrimary,
    error: c.missed,
    onError: Colors.white,
    errorContainer: brightness == Brightness.dark
        ? const Color(0xFF5C1A16)
        : const Color(0xFFFCE8E6),
    onErrorContainer: c.missed,
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceVariant,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: c.ink,
    onInverseSurface: c.canvas,
    inversePrimary: c.primaryContainer,
    surfaceTint: c.primary,
  );
}

Color scaffoldBackgroundFor(
  Brightness brightness, {
  AppPalette palette = AppPalette.azure,
}) =>
    PaletteColors.resolve(palette, brightness).scaffold;

ThemeData buildApp217Theme({
  required Brightness brightness,
  AppPalette palette = AppPalette.azure,
}) {
  final scheme = buildApp217ColorScheme(brightness, palette: palette);
  final c = PaletteColors.resolve(palette, brightness);

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
    labelLarge: body.labelLarge?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: body.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.scaffold,
    dividerColor: scheme.outline.withValues(alpha: 0.55),
    listTileTheme: ListTileThemeData(
      textColor: scheme.onSurface,
      iconColor: scheme.onSurfaceVariant,
      subtitleTextStyle: textTheme.bodyMedium,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return Color.alphaBlend(
          scheme.onSurface.withValues(alpha: 0.18),
          scheme.surface,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.onSurface;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.06),
            scheme.surface,
          );
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
      secondaryLabelStyle:
          textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
      side: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.headlineMedium?.copyWith(fontSize: 24),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.primary),
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
