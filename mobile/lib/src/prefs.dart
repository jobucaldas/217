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
  static const reminderHintDismissedKey = 'reminder_hint_dismissed';

  Future<({ThemeMode mode, AppPalette palette})> load() async {
    final modeRaw = await _storage.read(key: themeModeKey);
    final paletteRaw = await _storage.read(key: paletteKey);
    return (
      mode: _parseThemeMode(modeRaw),
      palette: AppPaletteX.fromId(paletteRaw),
    );
  }

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
