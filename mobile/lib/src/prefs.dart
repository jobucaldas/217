import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'i18n.dart';
import 'theme/palette.dart';

/// Persists appearance across auth and restarts.
class AppearancePrefs {
  AppearancePrefs({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const themeModeKey = 'theme_mode';
  static const paletteKey = 'app_palette';
  static const languageKey = 'language';
  static const pendingInviteKey = 'pending_invite';
  static const selfHostCardDismissedKey = 'self_host_card_dismissed';
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

  /// Saved UI language, or null when nobody picked one yet.
  Future<AppLanguage?> loadLanguage() async =>
      AppLanguageX.tryFromId(await _storage.read(key: languageKey));

  Future<void> saveLanguage(AppLanguage language) =>
      _storage.write(key: languageKey, value: language.id);

  /// Invite code from an opened `/?invite=` link, kept across the AuthKit
  /// round trip until the signed-in user answers the join prompt.
  Future<String?> pendingInvite() => _storage.read(key: pendingInviteKey);

  Future<void> savePendingInvite(String code) =>
      _storage.write(key: pendingInviteKey, value: code);

  Future<void> clearPendingInvite() => _storage.delete(key: pendingInviteKey);

  Future<void> saveThemeMode(ThemeMode mode) =>
      _storage.write(key: themeModeKey, value: _themeModeId(mode));

  Future<void> savePalette(AppPalette palette) =>
      _storage.write(key: paletteKey, value: palette.id);

  Future<bool> reminderHintDismissed() async {
    final v = await _storage.read(key: reminderHintDismissedKey);
    return v == '1';
  }

  Future<bool> selfHostCardDismissed() async =>
      await _storage.read(key: selfHostCardDismissedKey) == '1';

  Future<void> dismissSelfHostCard() =>
      _storage.write(key: selfHostCardDismissedKey, value: '1');

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
