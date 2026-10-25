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
/// PMS 21710-21719, pill 21720-21729, pill repeats 21730-21829.
const partnerPmsIdBase = 21710;
const partnerPillIdBase = 21720;
const partnerAlertIdCount = 10;
const partnerPillRepeatIdBase = 21730;
const partnerPillRepeatIdCount = 100;

/// How many days ahead pill alerts are queued between syncs.
const pillAlertHorizonDays = 7;

/// Pill repeats are queued only for today and tomorrow, at most this many per
/// day. Two days at 48 is 96 ids, which fits [partnerPillRepeatIdCount] and
/// keeps the app well under Android's pending-alarm limit (~500).
const pillRepeatDays = 2;
const pillRepeatMaxPerDay = 48;

/// Plans partner alerts from the latest calendar data.
///
/// PMS: one alert on each predicted PMS start day at [PartnerAlertPreference.pmsTime].
/// Pill: one alert per day for [pillAlertHorizonDays] at the pill time, minus
/// today when today's pill is already logged. Each app sync replans, so a
/// logged pill cancels that day's alert.
/// Pill repeats (when [PartnerAlertPreference.pillRepeatMinutes] is set): for
/// today and tomorrow, alerts every N minutes on the grid anchored at the pill
/// time, after now, before 23:59, capped at [pillRepeatMaxPerDay] per day.
/// Today's repeats are skipped when today's pill is already logged.
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
      if (w.pmsStart.year <= 1) continue;
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
    if (pref.pillRepeatOn) {
      final gap = Duration(minutes: pref.pillRepeatMinutes);
      var repeatId = partnerPillRepeatIdBase;
      for (var d = 0; d < pillRepeatDays; d++) {
        if (d == 0 && todayLogged) continue;
        final dayStart = DateTime(now.year, now.month, now.day + d);
        final endOfDay =
            DateTime(dayStart.year, dayStart.month, dayStart.day, 23, 59);
        final firstAlert = DateTime(
            dayStart.year, dayStart.month, dayStart.day, t.hour, t.minute);
        var planned = 0;
        for (var when = firstAlert.add(gap);
            when.isBefore(endOfDay) && planned < pillRepeatMaxPerDay;
            when = when.add(gap)) {
          if (!when.isAfter(now)) continue;
          out.add(PlannedAlert(
            id: repeatId++,
            when: when,
            title: pillTitle,
            body: pillBody,
          ));
          planned++;
        }
      }
    }
  }
  return out;
}
