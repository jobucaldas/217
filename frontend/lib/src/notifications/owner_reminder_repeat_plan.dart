import 'reminder_schedule.dart';

/// One local notification to schedule at a device-local wall-clock time.
class PlannedReminderRepeat {
  const PlannedReminderRepeat({
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

/// How many of the horizon days get repeat reminders. Repeats only replan
/// on sync, so if the owner doesn't open the app for days, repeats queued
/// for days 3+ would keep pinging every [repeatMinutes] on each of those
/// future days, undetected and unresolved until the next sync. Keeping this
/// to today and tomorrow bounds that noise and keeps well clear of
/// Android's per-app pending-alarm limit.
const ownerReminderRepeatHorizonDays = 2;

/// Bounds how many repeats a single day can schedule, so a very short
/// interval cannot tile an entire day with hundreds of alarms.
const maxOwnerReminderRepeatsPerDay = 48;

/// Notification ids reserved for the owner's own daily reminder repeat.
/// Does not collide with the daily reminder (21701) or the partner alert
/// ranges (21710-21719 PMS, 21720-21729 pill, 21800-21895 pill repeat).
/// One block of [maxOwnerReminderRepeatsPerDay] ids per horizon day:
/// id = ownerReminderRepeatIdBase + day * maxOwnerReminderRepeatsPerDay + occurrence.
const ownerReminderRepeatIdBase = 21900;
const ownerReminderRepeatIdCount =
    ownerReminderRepeatHorizonDays * maxOwnerReminderRepeatsPerDay;

/// Plans the owner's own "pill not logged" reminder repeats.
///
/// When [enabled] (the daily reminder itself) and [repeatEnabled], each of
/// the first [ownerReminderRepeatHorizonDays] days (today and tomorrow)
/// gets up to [maxOwnerReminderRepeatsPerDay] extra reminders every
/// [repeatMinutes] after that day's reminder time ([timeHhMm]), capped at
/// 23:59 local (never rolls into the next day). Today's repeats are skipped
/// entirely once [todayLogged]; each sync replans from scratch, so logging
/// the pill (or disabling the reminder/repeat) clears today's repeats on
/// the next sync.
List<PlannedReminderRepeat> planOwnerReminderRepeat({
  required DateTime now,
  required bool enabled,
  required bool repeatEnabled,
  required int repeatMinutes,
  required String timeHhMm,
  required bool todayLogged,
  required String title,
  required String body,
}) {
  final out = <PlannedReminderRepeat>[];
  if (!enabled || !repeatEnabled || repeatMinutes < 1) return out;
  final t = parseReminderTime(timeHhMm);
  for (var d = 0; d < ownerReminderRepeatHorizonDays; d++) {
    if (d == 0 && todayLogged) continue;
    final base =
        DateTime(now.year, now.month, now.day + d, t.hour, t.minute);
    // Never roll into the next day: 23:59 local is the hard cutoff.
    final endOfDay = DateTime(now.year, now.month, now.day + d, 23, 59);
    for (var r = 0; r < maxOwnerReminderRepeatsPerDay; r++) {
      final when = base.add(Duration(minutes: repeatMinutes * (r + 1)));
      if (when.isAfter(endOfDay)) break;
      if (!when.isAfter(now)) continue;
      out.add(PlannedReminderRepeat(
        id: ownerReminderRepeatIdBase + d * maxOwnerReminderRepeatsPerDay + r,
        when: when,
        title: title,
        body: body,
      ));
    }
  }
  return out;
}
