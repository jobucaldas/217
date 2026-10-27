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

/// How many of those horizon days also get repeat alerts. Repeats only
/// replan on sync, so if a partner doesn't open the app for days, repeats
/// queued for days 3+ would keep pinging every
/// [PartnerAlertPreference.pillRepeatMinutes] on each of those future days,
/// undetected and unresolved until the next sync. Keeping this to today and
/// tomorrow bounds that noise and keeps well clear of Android's per-app
/// pending-alarm limit.
const pillRepeatHorizonDays = 2;

/// Notification ids reserved for the pill repeat (does not overlap 21710-21729
/// above). One block of [maxPillRepeatsPerDay] ids per repeat horizon day:
/// id = partnerPillRepeatIdBase + day * maxPillRepeatsPerDay + occurrence.
const partnerPillRepeatIdBase = 21800;

/// Bounds how many repeats a single day can schedule, so a very short
/// interval cannot tile an entire day with hundreds of alarms (stays well
/// within Android's pending-alarm budget together with the other partner
/// alert ranges above).
const maxPillRepeatsPerDay = 48;

const partnerPillRepeatIdCount = pillRepeatHorizonDays * maxPillRepeatsPerDay;

/// Plans partner alerts from the latest calendar data.
///
/// PMS: one alert on each predicted PMS start day at [PartnerAlertPreference.pmsTime].
/// Pill: one alert per day for [pillAlertHorizonDays] at the pill time, minus
/// today when today's pill is already logged. Each app sync replans, so a
/// logged pill cancels that day's alert (and its repeats, below).
///
/// Pill repeat: when [PartnerAlertPreference.pillRepeatEnabled], each of the
/// first [pillRepeatHorizonDays] horizon days also gets up to
/// [maxPillRepeatsPerDay] extra alerts every
/// [PartnerAlertPreference.pillRepeatMinutes] after that day's pill time,
/// capped at 23:59 local (never rolls into the next day). Repeats are not
/// queued for days beyond [pillRepeatHorizonDays] (see its doc comment).
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
      if (when.isAfter(now)) {
        out.add(PlannedAlert(
          id: partnerPillIdBase + d,
          when: when,
          title: pillTitle,
          body: pillBody,
        ));
      }
      if (pref.pillRepeatEnabled &&
          pref.pillRepeatMinutes >= 1 &&
          d < pillRepeatHorizonDays) {
        // Never roll into the next day: 23:59 local is the hard cutoff.
        final endOfDay =
            DateTime(now.year, now.month, now.day + d, 23, 59);
        for (var r = 0; r < maxPillRepeatsPerDay; r++) {
          final repeatWhen =
              when.add(Duration(minutes: pref.pillRepeatMinutes * (r + 1)));
          if (repeatWhen.isAfter(endOfDay)) break;
          if (!repeatWhen.isAfter(now)) continue;
          out.add(PlannedAlert(
            id: partnerPillRepeatIdBase + d * maxPillRepeatsPerDay + r,
            when: repeatWhen,
            title: pillTitle,
            body: pillBody,
          ));
        }
      }
    }
  }
  return out;
}
