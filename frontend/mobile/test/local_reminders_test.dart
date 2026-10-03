import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/notifications/reminder_schedule.dart';

void main() {
  group('parseReminderTime', () {
    test('parses HH:mm', () {
      expect(parseReminderTime('09:30'), (hour: 9, minute: 30));
      expect(parseReminderTime('21:05'), (hour: 21, minute: 5));
    });

    test('falls back and clamps', () {
      expect(parseReminderTime(''), (hour: 9, minute: 0));
      expect(parseReminderTime('99:99'), (hour: 23, minute: 59));
      expect(parseReminderTime('7'), (hour: 7, minute: 0));
    });
  });

  group('nextDailyOccurrence', () {
    test('same day when still ahead', () {
      final now = DateTime(2026, 10, 1, 8, 0);
      final next = nextDailyOccurrence(now, 9, 0);
      expect(next, DateTime(2026, 10, 1, 9, 0));
    });

    test('rolls to tomorrow when past', () {
      final now = DateTime(2026, 10, 1, 9, 0);
      final next = nextDailyOccurrence(now, 9, 0);
      expect(next, DateTime(2026, 10, 2, 9, 0));
    });
  });

  group('LocalReminderSyncResult', () {
    test('ok / active flags', () {
      expect(
        const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled).ok,
        isTrue,
      );
      expect(
        const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled)
            .localDeliveryActive,
        isTrue,
      );
      expect(
        const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled).ok,
        isTrue,
      );
      expect(
        const LocalReminderSyncResult(LocalReminderSyncStatus.permissionDenied)
            .ok,
        isFalse,
      );
      expect(
        const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported)
            .localDeliveryActive,
        isFalse,
      );
    });
  });
}
