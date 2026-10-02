import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'theme/palette.dart';

/// Persists appearance across auth and restarts.
class AppearancePrefs {
  AppearancePrefs({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const themeModeKey = 'theme_mode';
  static const paletteKey = 'app_palette';
  static const languageKey = 'language';
  static const reminderHintDismissedKey = 'reminder_hint_dismissed';
  static const fabSideKey = 'today_fab_side';
  static const fabBottomKey = 'today_fab_bottom';

  Future<({ThemeMode mode, AppPalette palette})> load() async {
    final modeRaw = await _storage.read(key: themeModeKey);
    final paletteRaw = await _storage.read(key: paletteKey);
    return (
      mode: _parseThemeMode(modeRaw),
      palette: AppPaletteX.fromId(paletteRaw),
    );
  }

  /// Saved UI language: true = Português, false = English, null = not chosen.
  Future<bool?> loadPortuguese() async {
    switch (await _storage.read(key: languageKey)) {
      case 'pt':
        return true;
      case 'en':
        return false;
      default:
        return null;
    }
  }

  Future<void> savePortuguese(bool portuguese) =>
      _storage.write(key: languageKey, value: portuguese ? 'pt' : 'en');

  Future<void> saveThemeMode(ThemeMode mode) =>
      _storage.write(key: themeModeKey, value: _themeModeId(mode));

  Future<void> savePalette(AppPalette palette) =>
      _storage.write(key: paletteKey, value: palette.id);

  Future<bool> reminderHintDismissed() async {
    final v = await _storage.read(key: reminderHintDismissedKey);
    return v == '1';
  }

  Future<void> dismissReminderHint() =>
      _storage.write(key: reminderHintDismissedKey, value: '1');

  /// Magnetic today FAB: `right` (default) or `left`, plus bottom inset in logical px.
  Future<({bool right, double bottom})> loadFabPosition() async {
    final side = await _storage.read(key: fabSideKey);
    final bottomRaw = await _storage.read(key: fabBottomKey);
    final bottom = double.tryParse(bottomRaw ?? '') ?? 16.0;
    return (right: side != 'left', bottom: bottom.clamp(8.0, 400.0).toDouble());
  }

  Future<void> saveFabPosition({required bool right, required double bottom}) =>
      Future.wait([
        _storage.write(key: fabSideKey, value: right ? 'right' : 'left'),
        _storage.write(key: fabBottomKey, value: bottom.toStringAsFixed(1)),
      ]);

  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeId(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
