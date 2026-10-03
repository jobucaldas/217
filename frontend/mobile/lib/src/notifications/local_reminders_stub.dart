import 'partner_alert_plan.dart';
import 'reminder_schedule.dart';

/// Default for non-IO / non-HTML (tests use conditional imports).
bool get supportsLocalReminders => false;

Future<LocalReminderSyncResult> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) async =>
    const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);

Future<LocalReminderSyncStatus> syncPartnerAlerts(
  List<PlannedAlert> alerts,
) async =>
    LocalReminderSyncStatus.unsupported;
