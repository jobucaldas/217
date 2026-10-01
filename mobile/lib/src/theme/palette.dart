import 'package:flutter/material.dart';

/// Accent families for 217 chrome. Taken/missed stay semantic green/red.
enum AppPalette {
  /// Current forest default.
  forest,

  /// Brighter mint accent (#21C68F).
  mint,

  /// Plum accent (#53134B).
  plum,
}

extension AppPaletteX on AppPalette {
  String get id => name;

  static AppPalette fromId(String? raw) {
    switch (raw) {
      case 'mint':
        return AppPalette.mint;
      case 'plum':
        return AppPalette.plum;
      case 'forest':
      default:
        return AppPalette.forest;
    }
  }

  /// Swatch shown in the settings picker.
  Color get swatch {
    switch (this) {
      case AppPalette.forest:
        return const Color(0xFF1F6F5B);
      case AppPalette.mint:
        return const Color(0xFF21C68F);
      case AppPalette.plum:
        return const Color(0xFF53134B);
    }
  }
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
    switch (palette) {
      case AppPalette.forest:
        return dark ? _forestDark : _forestLight;
      case AppPalette.mint:
        return dark ? _mintDark : _mintLight;
      case AppPalette.plum:
        return dark ? _plumDark : _plumLight;
    }
  }

  static const _forestLight = PaletteColors(
    primary: Color(0xFF1F6F5B),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD8EDE4),
    onPrimaryContainer: Color(0xFF134A3D),
    secondary: Color(0xFF122018),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE4EEE8),
    onSecondaryContainer: Color(0xFF122018),
    surface: Color(0xFFFFFCF7),
    onSurface: Color(0xFF122018),
    onSurfaceVariant: Color(0xFF5C7264),
    outline: Color(0xFFCFDDD4),
    outlineVariant: Color(0xFFD8EDE4),
    scaffold: Color(0xFFF2F6F3),
    ink: Color(0xFF122018),
    canvas: Color(0xFFF2F6F3),
    taken: Color(0xFF1B7A4A),
    missed: Color(0xFFB42318),
    takenFill: Color(0xFF1B7A4A),
    missedFill: Color(0xFFB42318),
    onFilledCell: Colors.white,
  );

  static const _forestDark = PaletteColors(
    primary: Color(0xFF7BC4AE),
    onPrimary: Color(0xFF122018),
    primaryContainer: Color(0xFF134A3D),
    onPrimaryContainer: Color(0xFFD8EDE4),
    secondary: Color(0xFFC5D4CB),
    onSecondary: Color(0xFF122018),
    secondaryContainer: Color(0xFF24352C),
    onSecondaryContainer: Color(0xFFD8EDE4),
    surface: Color(0xFF101916),
    onSurface: Color(0xFFE7F0EA),
    onSurfaceVariant: Color(0xFFA8BDB2),
    outline: Color(0xFF3D5247),
    outlineVariant: Color(0xFF24352C),
    scaffold: Color(0xFF0C1411),
    ink: Color(0xFF122018),
    canvas: Color(0xFF0C1411),
    taken: Color(0xFF3DDC8A),
    missed: Color(0xFFFF8A80),
    takenFill: Color(0xFF145C38),
    missedFill: Color(0xFF8B1E18),
    onFilledCell: Color(0xFFF4FFF8),
  );

  static const _mintLight = PaletteColors(
    primary: Color(0xFF21C68F),
    onPrimary: Color(0xFF06281C),
    primaryContainer: Color(0xFFD2F5E8),
    onPrimaryContainer: Color(0xFF0A4A35),
    secondary: Color(0xFF163328),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE3F4ED),
    onSecondaryContainer: Color(0xFF163328),
    surface: Color(0xFFFAFFFC),
    onSurface: Color(0xFF12241C),
    onSurfaceVariant: Color(0xFF4A6B5C),
    outline: Color(0xFFBFDCCC),
    outlineVariant: Color(0xFFD2F5E8),
    scaffold: Color(0xFFEFF8F3),
    ink: Color(0xFF12241C),
    canvas: Color(0xFFEFF8F3),
    taken: Color(0xFF14996C),
    missed: Color(0xFFB42318),
    takenFill: Color(0xFF14996C),
    missedFill: Color(0xFFB42318),
    onFilledCell: Colors.white,
  );

  static const _mintDark = PaletteColors(
    primary: Color(0xFF5EE0B0),
    onPrimary: Color(0xFF06281C),
    primaryContainer: Color(0xFF0E5C42),
    onPrimaryContainer: Color(0xFFD2F5E8),
    secondary: Color(0xFFC5E6D6),
    onSecondary: Color(0xFF06281C),
    secondaryContainer: Color(0xFF1C3329),
    onSecondaryContainer: Color(0xFFD2F5E8),
    surface: Color(0xFF0E1613),
    onSurface: Color(0xFFE6F7EF),
    onSurfaceVariant: Color(0xFFA3C4B4),
    outline: Color(0xFF355447),
    outlineVariant: Color(0xFF1C3329),
    scaffold: Color(0xFF0A1210),
    ink: Color(0xFF12241C),
    canvas: Color(0xFF0A1210),
    taken: Color(0xFF5EE0B0),
    missed: Color(0xFFFF8A80),
    takenFill: Color(0xFF0E5C42),
    missedFill: Color(0xFF8B1E18),
    onFilledCell: Color(0xFFF2FFF9),
  );

  static const _plumLight = PaletteColors(
    primary: Color(0xFF53134B),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF3E4EF),
    onPrimaryContainer: Color(0xFF3A0C34),
    secondary: Color(0xFF2A1426),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF0E6ED),
    onSecondaryContainer: Color(0xFF2A1426),
    surface: Color(0xFFFFFBFC),
    onSurface: Color(0xFF241018),
    onSurfaceVariant: Color(0xFF6B5464),
    outline: Color(0xFFDCCAD6),
    outlineVariant: Color(0xFFF3E4EF),
    scaffold: Color(0xFFF8F2F6),
    ink: Color(0xFF241018),
    canvas: Color(0xFFF8F2F6),
    taken: Color(0xFF1B7A4A),
    missed: Color(0xFFB42318),
    takenFill: Color(0xFF1B7A4A),
    missedFill: Color(0xFFB42318),
    onFilledCell: Colors.white,
  );

  static const _plumDark = PaletteColors(
    primary: Color(0xFFE2A4D2),
    onPrimary: Color(0xFF3A0C34),
    primaryContainer: Color(0xFF53134B),
    onPrimaryContainer: Color(0xFFF8E7F3),
    secondary: Color(0xFFE4CDDC),
    onSecondary: Color(0xFF2A1426),
    secondaryContainer: Color(0xFF3A2434),
    onSecondaryContainer: Color(0xFFF3E4EF),
    surface: Color(0xFF161016),
    onSurface: Color(0xFFF5EAF1),
    onSurfaceVariant: Color(0xFFC4A8BA),
    outline: Color(0xFF56404F),
    outlineVariant: Color(0xFF3A2434),
    scaffold: Color(0xFF110C11),
    ink: Color(0xFF241018),
    canvas: Color(0xFF110C11),
    taken: Color(0xFF5EE0A8),
    missed: Color(0xFFFF8A80),
    takenFill: Color(0xFF145C38),
    missedFill: Color(0xFF8B1E18),
    onFilledCell: Color(0xFFFFF8FC),
  );
}
