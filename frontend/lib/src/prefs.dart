import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'i18n.dart';
import 'models.dart';
import 'secure_storage.dart';
import 'theme/palette.dart';

/// Persists appearance across auth and restarts.
class AppearancePrefs {
  AppearancePrefs({FlutterSecureStorage? storage})
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;

  static const themeModeKey = 'theme_mode';
  static const paletteKey = 'app_palette';
  static const languageKey = 'language';
  static const pendingInviteKey = 'pending_invite';
  static const reminderHintDismissedKey = 'reminder_hint_dismissed';
  static const autoUpdateKey = 'auto_update';
  static const messageNotificationsKey = 'message_notifications';
  static const messagesNotifiedKeyPrefix = 'messages_notified_';
  static const messagePermissionAskedKey = 'message_permission_asked';
  static const messagesForegroundAtKey = 'messages_foreground_at';
  static const stageSuggestionDismissedPrefix = 'stage_suggestion_dismissed_';
  static const stageSuggestionSeenPrefix = 'stage_suggestion_seen_';
  static const syncStateKey = 'sync_state';
  static const appSyncStateKey = 'sync_state_app';
  static const partnerOwnerNamePrefix = 'partner_owner_name_';
  static const partnerAlertsEnabledPrefix = 'partner_alerts_enabled_';
  static const partnerAlertsActiveUserKey = 'partner_alerts_active_user';
  static const partnerLastPlanDatePrefix = 'partner_last_plan_date_';

  /// Stage suggestion [userId] dismissed on this device (null: none).
  Future<String?> stageSuggestionDismissed(String userId) =>
      _storage.read(key: stageSuggestionDismissedPrefix + userId);

  Future<void> saveStageSuggestionDismissed(String userId, String stage) =>
      _storage.write(key: stageSuggestionDismissedPrefix + userId, value: stage);

  /// Stage suggestion whose calendar banner already timed out for [userId].
  Future<String?> stageSuggestionSeen(String userId) =>
      _storage.read(key: stageSuggestionSeenPrefix + userId);

  Future<void> saveStageSuggestionSeen(String userId, String stage) =>
      _storage.write(key: stageSuggestionSeenPrefix + userId, value: stage);

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

  /// Invite code from an opened `/app/?invite=` link, kept across the AuthKit
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

  Future<void> dismissReminderHint() =>
      _storage.write(key: reminderHintDismissedKey, value: '1');

  /// Reminders were toggled: the calendar bubble may explain them again.
  Future<void> resetReminderHint() =>
      _storage.delete(key: reminderHintDismissedKey);

  /// Opt-in update check on Android. Off unless the user turned it on.
  Future<bool> autoUpdateEnabled() async {
    final v = await _storage.read(key: autoUpdateKey);
    return v == '1';
  }

  Future<void> saveAutoUpdate(bool enabled) =>
      _storage.write(key: autoUpdateKey, value: enabled ? '1' : '0');

  /// Local "new message" notifications. On unless the user turned them off.
  Future<bool> messageNotificationsEnabled() async =>
      await _storage.read(key: messageNotificationsKey) != '0';

  Future<void> saveMessageNotifications(bool enabled) =>
      _storage.write(key: messageNotificationsKey, value: enabled ? '1' : '0');

  /// Whether the notification permission was already asked for messages.
  Future<bool> messagePermissionAsked() async =>
      await _storage.read(key: messagePermissionAskedKey) == '1';

  Future<void> saveMessagePermissionAsked() =>
      _storage.write(key: messagePermissionAskedKey, value: '1');

  /// Server time of the newest message already announced or seen by
  /// [userId] on this device, so a message is never notified twice.
  Future<DateTime?> messagesNotifiedUpTo(String userId) async =>
      DateTime.tryParse(
          await _storage.read(key: messagesNotifiedKeyPrefix + userId) ?? '');

  /// Only ever moves forward, so a slower check cannot rewind the mark and
  /// announce a message again.
  Future<void> saveMessagesNotifiedUpTo(String userId, DateTime at) async {
    final current = await messagesNotifiedUpTo(userId);
    if (current != null && !at.isAfter(current)) return;
    await _storage.write(
        key: messagesNotifiedKeyPrefix + userId,
        value: at.toUtc().toIso8601String());
  }

  /// When the app last checked messages in the foreground (null: not in
  /// the foreground). The background worker leaves those checks to it.
  Future<DateTime?> messagesForegroundAt() async => DateTime.tryParse(
      await _storage.read(key: messagesForegroundAtKey) ?? '');

  Future<void> saveMessagesForegroundAt(DateTime? at) => at == null
      ? _storage.delete(key: messagesForegroundAtKey)
      : _storage.write(
          key: messagesForegroundAtKey, value: at.toUtc().toIso8601String());

  Future<({String server, SyncStatus status})?> _readSyncState(
      String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        server: (json['server'] as String?) ?? '',
        status: SyncStatus.fromJson(json),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSyncState(
          String key, String server, SyncStatus status) =>
      _storage.write(
        key: key,
        value: jsonEncode({'server': server, ...status.toJson()}),
      );

  /// The last `/api/sync/status` answer handled by the background worker.
  /// Kept separate from [appSyncState] so a background check advancing its
  /// ETag never causes the live app to skip refreshing on resume.
  Future<({String server, SyncStatus status})?> syncState() =>
      _readSyncState(syncStateKey);

  Future<void> saveSyncState(String server, SyncStatus status) =>
      _writeSyncState(syncStateKey, server, status);

  /// The last `/api/sync/status` answer handled by the live foreground app.
  Future<({String server, SyncStatus status})?> appSyncState() =>
      _readSyncState(appSyncStateKey);

  Future<void> saveAppSyncState(String server, SyncStatus status) =>
      _writeSyncState(appSyncStateKey, server, status);

  /// Sign-out, account or server change: the next check starts fresh.
  Future<void> clearSyncState() async {
    await _storage.delete(key: syncStateKey);
    await _storage.delete(key: appSyncStateKey);
    await _storage.delete(key: partnerAlertsActiveUserKey);
  }

  /// The owner's name as the partner's last sync saw it, so replanned
  /// alerts in the background name her like the foreground ones.
  Future<String> partnerOwnerName(String userId) async =>
      await _storage.read(key: partnerOwnerNamePrefix + userId) ?? '';

  Future<void> savePartnerOwnerName(String userId, String name) =>
      _storage.write(key: partnerOwnerNamePrefix + userId, value: name);

  /// Whether [userId] has a partner alert (PMS or pill) switched on, as of
  /// the last sync: tells the worker to run before any request is made.
  Future<bool> partnerAlertsEnabled(String userId) async =>
      await _storage.read(key: partnerAlertsEnabledPrefix + userId) == '1';

  Future<void> savePartnerAlertsEnabled(String userId, bool enabled) async {
    await _storage.write(
        key: partnerAlertsEnabledPrefix + userId, value: enabled ? '1' : '0');
    if (enabled) {
      await _storage.write(key: partnerAlertsActiveUserKey, value: userId);
    } else if (await _storage.read(key: partnerAlertsActiveUserKey) == userId) {
      await _storage.delete(key: partnerAlertsActiveUserKey);
    }
  }

  /// Whether the background worker should poll for partner alerts. When
  /// [userId] is not yet known (before the first sync baseline is saved),
  /// falls back to the last partner account that enabled alerts on this device.
  Future<bool> hasPartnerAlertsForWorker({String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      return partnerAlertsEnabled(userId);
    }
    final activeUser = await _storage.read(key: partnerAlertsActiveUserKey);
    if (activeUser == null || activeUser.isEmpty) return false;
    return partnerAlertsEnabled(activeUser);
  }

  /// Local calendar date (YYYY-MM-DD) for which [userId]'s partner alerts
  /// were last planned, so the background worker refreshes once per new day
  /// even when the server returns 304.
  Future<String?> partnerLastPlanDate(String userId) =>
      _storage.read(key: partnerLastPlanDatePrefix + userId);

  Future<void> savePartnerLastPlanDate(String userId, String date) =>
      _storage.write(key: partnerLastPlanDatePrefix + userId, value: date);

  /// Drops what was kept for [userId]'s calendar (sign-out, deletion).
  Future<void> clearPartnerCache(String userId) async {
    await _storage.delete(key: partnerOwnerNamePrefix + userId);
    await _storage.delete(key: partnerAlertsEnabledPrefix + userId);
    await _storage.delete(key: partnerLastPlanDatePrefix + userId);
    if (await _storage.read(key: partnerAlertsActiveUserKey) == userId) {
      await _storage.delete(key: partnerAlertsActiveUserKey);
    }
  }

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
