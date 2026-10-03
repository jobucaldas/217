import '../models.dart';
import 'reminder_schedule.dart';

/// One local notification to schedule at a device-local wall-clock time.
class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;
}

/// Notification ids reserved for partner alerts (daily reminder uses 21701).
const partnerPmsIdBase = 21710;
const partnerPillIdBase = 21720;
const partnerAlertIdCount = 10;

/// How many days ahead pill alerts are queued between syncs.
const pillAlertHorizonDays = 7;

/// Plans partner alerts from the latest calendar data.
///
/// PMS: one alert on each predicted PMS start day at [PartnerAlertPreference.pmsTime].
/// Pill: one alert per day for [pillAlertHorizonDays] at the pill time, minus
/// today when today's pill is already logged. Each app sync replans, so a
/// logged pill cancels that day's alert.
List<PlannedAlert> planPartnerAlerts({
  required DateTime now,
  required PartnerAlertPreference pref,
  required CycleInfo cycle,
  required bool todayLogged,
  required String Function(CycleWindow window) pmsTitle,
  required String Function(CycleWindow window) pmsBody,
  required String pillTitle,
  required String pillBody,
}) {
  final out = <PlannedAlert>[];
  if (pref.pmsEnabled) {
    final t = parseReminderTime(pref.pmsTime);
    var i = 0;
    for (final w in cycle.predictions) {
      if (i >= partnerAlertIdCount) break;
      final when = DateTime(
        w.pmsStart.year,
        w.pmsStart.month,
        w.pmsStart.day,
        t.hour,
        t.minute,
      );
      if (!when.isAfter(now)) continue;
      out.add(PlannedAlert(
        id: partnerPmsIdBase + i,
        when: when,
        title: pmsTitle(w),
        body: pmsBody(w),
      ));
      i++;
    }
  }
  if (pref.pillEnabled) {
    final t = parseReminderTime(pref.pillTime);
    for (var d = 0; d < pillAlertHorizonDays; d++) {
      if (d == 0 && todayLogged) continue;
      final when = DateTime(now.year, now.month, now.day + d, t.hour, t.minute);
      if (!when.isAfter(now)) continue;
      out.add(PlannedAlert(
        id: partnerPillIdBase + d,
        when: when,
        title: pillTitle,
        body: pillBody,
      ));
    }
  }
  return out;
}
