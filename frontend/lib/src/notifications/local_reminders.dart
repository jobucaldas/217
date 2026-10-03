import 'partner_alert_plan.dart';
import 'reminder_schedule.dart';
import 'local_reminders_stub.dart'
    if (dart.library.html) 'local_reminders_web.dart'
    if (dart.library.io) 'local_reminders_io.dart' as impl;

export 'partner_alert_plan.dart';
export 'reminder_schedule.dart';

/// True when this build can attempt OS/browser local notifications.
bool get supportsLocalReminders => impl.supportsLocalReminders;

/// Schedules or cancels a daily local reminder. Never throws for UI callers.
Future<LocalReminderSyncResult> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) =>
    impl.syncLocalDailyReminder(
      enabled: enabled,
      timeHhMm: timeHhMm,
      title: title,
      body: body,
    );

/// Replaces all scheduled partner alerts with [alerts]. Never throws.
Future<LocalReminderSyncStatus> syncPartnerAlerts(List<PlannedAlert> alerts) =>
    impl.syncPartnerAlerts(alerts);
