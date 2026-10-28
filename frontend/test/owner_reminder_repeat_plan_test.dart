import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/notifications/owner_reminder_repeat_plan.dart';
import 'package:a217/src/notifications/partner_alert_plan.dart';

void main() {
  List<PlannedReminderRepeat> repeatsForDay(
    List<PlannedReminderRepeat> repeats,
    int day,
  ) {
    final base = ownerReminderRepeatIdBase + day * maxOwnerReminderRepeatsPerDay;
    return repeats
        .where((r) => r.id >= base && r.id < base + maxOwnerReminderRepeatsPerDay)
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
  }

  List<PlannedReminderRepeat> plan({
    bool enabled = true,
    bool repeatEnabled = true,
    int repeatMinutes = 30,
    String timeHhMm = '21:00',
    bool logged = false,
    DateTime? now,
  }) =>
      planOwnerReminderRepeat(
        now: now ?? DateTime(2026, 10, 3),
        enabled: enabled,
        repeatEnabled: repeatEnabled,
        repeatMinutes: repeatMinutes,
        timeHhMm: timeHhMm,
        todayLogged: logged,
        title: '217',
        body: 'Record today',
      );

  test('off by default even with the daily reminder on', () {
    expect(plan(repeatEnabled: false), isEmpty);
  });

  test('off entirely when the daily reminder itself is disabled', () {
    expect(plan(enabled: false), isEmpty);
  });

  test('fires every X minutes after the reminder time, capped at 23:59', () {
    final day0 = repeatsForDay(plan(timeHhMm: '21:00', repeatMinutes: 30), 0);
    expect(day0.map((r) => r.when), [
      DateTime(2026, 10, 3, 21, 30),
      DateTime(2026, 10, 3, 22, 0),
      DateTime(2026, 10, 3, 22, 30),
      DateTime(2026, 10, 3, 23, 0),
      DateTime(2026, 10, 3, 23, 30),
    ]);
    // Never rolls into the next day (24:00 would be the 6th occurrence).
    expect(day0.every((r) => r.when.day == 3), isTrue);
  });

  test('stops once today is logged, tomorrow stays scheduled', () {
    final repeats = plan(logged: true);
    expect(repeatsForDay(repeats, 0), isEmpty);
    expect(repeatsForDay(repeats, 1), isNotEmpty);
  });

  test('per-day count is bounded even at a 1-minute interval', () {
    final repeats = plan(timeHhMm: '00:00', repeatMinutes: 1);
    expect(repeatsForDay(repeats, 0).length, maxOwnerReminderRepeatsPerDay);
  });

  test('today+tomorrow horizon: nothing beyond day 1', () {
    final repeats = plan(timeHhMm: '00:00', repeatMinutes: 1);
    final total = repeats.length;
    expect(total, ownerReminderRepeatHorizonDays * maxOwnerReminderRepeatsPerDay);
    expect(ownerReminderRepeatHorizonDays, 2);
  });

  test('ids are unique, within the reserved range, and never collide with '
      'the daily reminder or partner alert ranges', () {
    final ids = plan(repeatMinutes: 15).map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(
        id >= ownerReminderRepeatIdBase &&
            id < ownerReminderRepeatIdBase + ownerReminderRepeatIdCount,
        isTrue,
        reason: 'id $id',
      );
    }
    const dailyReminderId = 21701;
    expect(ids.contains(dailyReminderId), isFalse);
    for (final id in ids) {
      final inPartnerPms =
          id >= partnerPmsIdBase && id < partnerPmsIdBase + partnerAlertIdCount;
      final inPartnerPill = id >= partnerPillIdBase &&
          id < partnerPillIdBase + partnerAlertIdCount;
      final inPartnerPillRepeat = id >= partnerPillRepeatIdBase &&
          id < partnerPillRepeatIdBase + partnerPillRepeatIdCount;
      expect(inPartnerPms || inPartnerPill || inPartnerPillRepeat, isFalse,
          reason: 'id $id collides with a partner alert range');
    }
    expect(ownerReminderRepeatIdBase >= partnerPillRepeatIdBase + partnerPillRepeatIdCount,
        isTrue);
  });

  test('replanning the same inputs twice is idempotent', () {
    final first = plan(repeatMinutes: 15);
    final second = plan(repeatMinutes: 15);
    expect(first.map((r) => r.id), second.map((r) => r.id));
    expect(first.map((r) => r.when), second.map((r) => r.when));
  });
}
