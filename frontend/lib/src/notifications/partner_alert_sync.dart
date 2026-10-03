import 'package:intl/intl.dart';

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
  DateTime? now,
}) {
  final day = DateFormat.MMMd(strings.dateLocale);
  final alerts = linked
      ? planPartnerAlerts(
          now: now ?? DateTime.now(),
          pref: pref,
          cycle: cycle,
          todayLogged: todayLogged,
          pmsTitle: (_) => strings.pmsNotifTitle,
          pmsBody: (w) =>
              strings.pmsNotifBody(ownerName, day.format(w.periodStart)),
          pillTitle: strings.pillNotifTitle,
          pillBody: strings.pillNotifBody(ownerName),
        )
      : const <PlannedAlert>[];
  return syncPartnerAlerts(alerts);
}
