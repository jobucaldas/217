import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

export 'palette.dart';

/// Status helpers used by calendar chrome (palette-aware).
abstract final class App217Colors {
  static Color statusTaken(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).taken;

  static Color statusMissed(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).missed;

  static Color cellTaken(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).takenFill;

  static Color cellMissed(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).missedFill;

  static Color onFilledCell(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).onFilledCell;

  static Color pms(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).pms;

  static Color period(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).period;

  static Color intimacy(Brightness b, [AppPalette palette = AppPalette.blue]) =>
      PaletteColors.resolve(palette, b).intimacy;
}

/// Colors only — safe for unit tests (no Google Fonts / binding).
ColorScheme buildApp217ColorScheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.blue,
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
  AppPalette palette = AppPalette.blue,
}) =>
    PaletteColors.resolve(palette, brightness).scaffold;

ThemeData buildApp217Theme({
  required Brightness brightness,
  AppPalette palette = AppPalette.blue,
}) {
  final scheme = buildApp217ColorScheme(brightness, palette: palette);
  final c = PaletteColors.resolve(palette, brightness);

  // Fraunces is the "217" wordmark's face and nothing else (see
  // [App217Typography]); every text theme style is Source Sans 3.
  // GoogleFonts' defaults carry the light-theme ink color; recolor every style
  // so framework-built text (dialog titles, pickers, menus) stays readable on
  // dark surfaces.
  final body = GoogleFonts.sourceSans3TextTheme().apply(
    displayColor: scheme.onSurface,
    bodyColor: scheme.onSurfaceVariant,
  );
  final textTheme = body.copyWith(
    headlineMedium: body.headlineMedium?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: 30,
      letterSpacing: -0.4,
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
    extensions: [
      App217Typography(
        wordmark: GoogleFonts.fraunces(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 24,
          height: 1.15,
        ),
        wordmarkLarge: GoogleFonts.fraunces(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
          fontSize: 56,
          height: 1.0,
        ),
      ),
    ],
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
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22),
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

/// The "217" wordmark's typography (Fraunces). Reserved for the logo: page
/// titles, headings and body copy use the regular [TextTheme].
@immutable
class App217Typography extends ThemeExtension<App217Typography> {
  const App217Typography({required this.wordmark, required this.wordmarkLarge});

  /// App bar logo.
  final TextStyle wordmark;

  /// Splash-sized logo (sign-in, server setup).
  final TextStyle wordmarkLarge;

  static App217Typography of(BuildContext context) {
    final theme = Theme.of(context);
    final own = theme.extension<App217Typography>();
    if (own != null) return own;
    final color = theme.colorScheme.onSurface;
    return App217Typography(
      wordmark: TextStyle(
          color: color, fontSize: 24, fontWeight: FontWeight.w600),
      wordmarkLarge: TextStyle(
          color: color, fontSize: 56, fontWeight: FontWeight.w600),
    );
  }

  @override
  App217Typography copyWith({TextStyle? wordmark, TextStyle? wordmarkLarge}) =>
      App217Typography(
        wordmark: wordmark ?? this.wordmark,
        wordmarkLarge: wordmarkLarge ?? this.wordmarkLarge,
      );

  @override
  App217Typography lerp(App217Typography? other, double t) {
    if (other == null) return this;
    return App217Typography(
      wordmark: TextStyle.lerp(wordmark, other.wordmark, t)!,
      wordmarkLarge: TextStyle.lerp(wordmarkLarge, other.wordmarkLarge, t)!,
    );
  }
}

/// The "217" logo set in its own typeface.
class Wordmark extends StatelessWidget {
  const Wordmark(this.text, {super.key, this.large = false, this.textAlign});

  final String text;
  final bool large;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final typography = App217Typography.of(context);
    return Text(
      text,
      textAlign: textAlign,
      style: large ? typography.wordmarkLarge : typography.wordmark,
    );
  }
}
