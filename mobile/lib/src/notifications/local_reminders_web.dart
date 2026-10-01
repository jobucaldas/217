// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'reminder_schedule.dart';

/// Web: no reliable background daily schedule without a service worker.
/// We still probe the Notification API so the UI can be honest.
bool get supportsLocalReminders => html.Notification.supported;

Future<LocalReminderSyncResult> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) async {
  if (!html.Notification.supported) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
  }

  if (!enabled) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
  }

  final permission = html.Notification.permission;
  var granted = permission == 'granted';
  if (permission == 'default') {
    final result = await html.Notification.requestPermission();
    granted = result == 'granted';
  }
  if (!granted) {
    return const LocalReminderSyncResult(
      LocalReminderSyncStatus.permissionDenied,
    );
  }

  // Browsers cannot schedule recurring OS alarms from a normal page.
  // Permission granted ≠ background daily delivery — callers should treat
  // web as needing server push (VAPID) for real delivery while showing
  // that the Notification API is allowed.
  return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
}
