import 'partner_alert_plan.dart';
import 'reminder_schedule.dart';
import 'local_reminders_stub.dart'
    if (dart.library.html) 'local_reminders_web.dart'
    if (dart.library.io) 'local_reminders_io.dart' as impl;

export 'message_alerts.dart';
export 'owner_reminder_repeat_plan.dart';
export 'partner_alert_plan.dart';
export 'reminder_schedule.dart';

/// True when this build can attempt OS/browser local notifications.
bool get supportsLocalReminders => impl.supportsLocalReminders;

/// Schedules or cancels a daily local reminder, and (when [repeatEnabled])
/// its "pill not logged" repeats every [repeatMinutes] until [todayLogged]
/// or 23:59 local. Never throws for UI callers.
Future<LocalReminderSyncResult> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
  bool repeatEnabled = false,
  int repeatMinutes = 15,
  bool todayLogged = false,
}) =>
    impl.syncLocalDailyReminder(
      enabled: enabled,
      timeHhMm: timeHhMm,
      title: title,
      body: body,
      repeatEnabled: repeatEnabled,
      repeatMinutes: repeatMinutes,
      todayLogged: todayLogged,
    );

/// Replaces all scheduled partner alerts with [alerts]. Never throws.
Future<LocalReminderSyncStatus> syncPartnerAlerts(List<PlannedAlert> alerts) =>
    impl.syncPartnerAlerts(alerts);

/// Shows (or replaces) the "new message" notification now. Never prompts for
/// permission and never throws: without permission nothing is shown.
Future<bool> showMessageNotification({
  required String title,
  required String body,
}) =>
    impl.showMessageNotification(title: title, body: body);

/// Asks for the notification permission (Android 13+). True when granted or
/// not needed; false when denied or unsupported.
Future<bool> requestNotificationPermission() =>
    impl.requestNotificationPermission();
