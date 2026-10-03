import 'package:flutter/material.dart';

/// Accent families for 217 chrome. Surfaces stay pinned neutrals;
/// taken/missed stay semantic green/red.
enum AppPalette {
  /// Default vivid blue accent.
  blue,

  /// Cyan/aqua accent.
  cyan,

  /// Vivid purple accent.
  purple,
}

extension AppPaletteX on AppPalette {
  String get id => name;

  /// Resolves stored ids. Legacy ids (`azure`, `mint`, `plum`, `forest`) and
  /// unknown values map to the current accents.
  static AppPalette fromId(String? raw) {
    switch (raw) {
      case 'cyan':
      case 'mint':
        return AppPalette.cyan;
      case 'purple':
      case 'plum':
        return AppPalette.purple;
      case 'blue':
      case 'azure':
      case 'forest':
      default:
        return AppPalette.blue;
    }
  }

  /// Swatch shown in the settings picker.
  Color get swatch {
    switch (this) {
      case AppPalette.blue:
        return const Color(0xFF2563EB);
      case AppPalette.cyan:
        return const Color(0xFF0891B2);
      case AppPalette.purple:
        return const Color(0xFFC026D3);
    }
  }
}

class _Accent {
  const _Accent({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
}

/// Resolved colors for one palette × brightness.
class PaletteColors {
  const PaletteColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.scaffold,
    required this.ink,
    required this.canvas,
    required this.taken,
    required this.missed,
    required this.takenFill,
    required this.missedFill,
    required this.onFilledCell,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color scaffold;
  final Color ink;
  final Color canvas;
  final Color taken;
  final Color missed;
  final Color takenFill;
  final Color missedFill;
  final Color onFilledCell;

  static PaletteColors resolve(AppPalette palette, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = _accentFor(palette, dark);
    return dark ? _composeDark(accent) : _composeLight(accent);
  }

  static _Accent _accentFor(AppPalette palette, bool dark) {
    switch (palette) {
      case AppPalette.blue:
        return dark ? _blueDark : _blueLight;
      case AppPalette.cyan:
        return dark ? _cyanDark : _cyanLight;
      case AppPalette.purple:
        return dark ? _purpleDark : _purpleLight;
    }
  }

  // Shared pinned neutrals — do not shift with accent.
  static const _lightScaffold = Color(0xFFF5F5F4);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightOnSurface = Color(0xFF1C1917);
  static const _lightOnVariant = Color(0xFF57534E);
  static const _lightOutline = Color(0xFFD6D3D1);
  static const _lightOutlineVariant = Color(0xFFE7E5E4);
  static const _lightSecondaryContainer = Color(0xFFE7E5E4);

  static const _darkScaffold = Color(0xFF121212);
  static const _darkSurface = Color(0xFF1C1C1C);
  static const _darkOnSurface = Color(0xFFF5F5F5);
  static const _darkOnVariant = Color(0xFFD4D4D4);
  static const _darkOutline = Color(0xFF404040);
  static const _darkOutlineVariant = Color(0xFF2A2A2A);
  static const _darkSecondaryContainer = Color(0xFF2A2A2A);

  // Semantic status (shared).
  static const _takenLight = Color(0xFF15803D);
  static const _missedLight = Color(0xFFB91C1C);
  static const _takenDark = Color(0xFF4ADE80);
  static const _missedDark = Color(0xFFFB7185);
  static const _takenFillDark = Color(0xFF14532D);
  static const _missedFillDark = Color(0xFF7F1D1D);

  static const _blueLight = _Accent(
    primary: Color(0xFF2563EB),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDBEAFE),
    onPrimaryContainer: Color(0xFF1E3A8A),
  );
  static const _blueDark = _Accent(
    primary: Color(0xFF60A5FA),
    onPrimary: Color(0xFF0B1220),
    primaryContainer: Color(0xFF1E3A8A),
    onPrimaryContainer: Color(0xFFDBEAFE),
  );

  static const _cyanLight = _Accent(
    primary: Color(0xFF0891B2),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCFFAFE),
    onPrimaryContainer: Color(0xFF164E63),
  );
  static const _cyanDark = _Accent(
    primary: Color(0xFF22D3EE),
    onPrimary: Color(0xFF083344),
    primaryContainer: Color(0xFF155E75),
    onPrimaryContainer: Color(0xFFCFFAFE),
  );

  static const _purpleLight = _Accent(
    primary: Color(0xFFC026D3),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFAE8FF),
    onPrimaryContainer: Color(0xFF701A75),
  );
  static const _purpleDark = _Accent(
    primary: Color(0xFFE879F9),
    onPrimary: Color(0xFF4A044E),
    primaryContainer: Color(0xFF86198F),
    onPrimaryContainer: Color(0xFFFAE8FF),
  );

  static PaletteColors _composeLight(_Accent a) => PaletteColors(
        primary: a.primary,
        onPrimary: a.onPrimary,
        primaryContainer: a.primaryContainer,
        onPrimaryContainer: a.onPrimaryContainer,
        secondary: _lightOnSurface,
        onSecondary: Colors.white,
        secondaryContainer: _lightSecondaryContainer,
        onSecondaryContainer: _lightOnSurface,
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        onSurfaceVariant: _lightOnVariant,
        outline: _lightOutline,
        outlineVariant: _lightOutlineVariant,
        scaffold: _lightScaffold,
        ink: _lightOnSurface,
        canvas: _lightScaffold,
        taken: _takenLight,
        missed: _missedLight,
        takenFill: _takenLight,
        missedFill: _missedLight,
        onFilledCell: Colors.white,
      );

  static PaletteColors _composeDark(_Accent a) => PaletteColors(
        primary: a.primary,
        onPrimary: a.onPrimary,
        primaryContainer: a.primaryContainer,
        onPrimaryContainer: a.onPrimaryContainer,
        secondary: _darkOnVariant,
        onSecondary: _darkScaffold,
        secondaryContainer: _darkSecondaryContainer,
        onSecondaryContainer: _darkOnSurface,
        surface: _darkSurface,
        onSurface: _darkOnSurface,
        onSurfaceVariant: _darkOnVariant,
        outline: _darkOutline,
        outlineVariant: _darkOutlineVariant,
        scaffold: _darkScaffold,
        ink: _darkOnSurface,
        canvas: _darkScaffold,
        taken: _takenDark,
        missed: _missedDark,
        takenFill: _takenFillDark,
        missedFill: _missedFillDark,
        onFilledCell: const Color(0xFFF5F5F5),
      );
}
