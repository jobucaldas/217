import '../i18n.dart';
import '../models.dart';
import 'local_reminders.dart';

/// Plans partner alerts from the latest calendar data and hands them to the
/// OS scheduler. Unlinked partners (or both toggles off) clear all alerts.
Future<LocalReminderSyncStatus> syncPartnerAlertsFrom({
  required Strings strings,
  required PartnerAlertPreference pref,
  required CycleInfo cycle,
  required bool linked,
  required bool todayLogged,
  required String ownerName,
  Future<LocalReminderSyncStatus> Function(List<PlannedAlert>)? scheduler,
  DateTime? now,
}) {
  final dates = strings.dates;
  final at = now ?? DateTime.now();
  final alerts = linked
      ? planPartnerAlerts(
          now: at,
          pref: pref,
          cycle: cycle,
          todayLogged: todayLogged,
          pmsTitle: (_) => strings.pmsNotifTitle,
          pmsBody: (w) => strings.pmsNotifBody(
            ownerName,
            dates.numericDayMonth(w.pmsStart),
            dates.numericDayMonth(w.pmsEnd),
          ),
          pillTitle: strings.pillNotifTitle,
          pillBody: (when) => strings.pillNotifBody(ownerName, dates.time(when)),
        )
      : const <PlannedAlert>[];
  return (scheduler ?? syncPartnerAlerts)(alerts);
}
