import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/notifications/daily_reminder_sync_queue.dart';
import 'package:a217/src/notifications/local_reminders.dart';

void main() {
  test('new settings intent wins after a delayed native reminder sync',
      () async {
    final started = Completer<void>();
    final finishSchedule = Completer<LocalReminderSyncResult>();
    final calls = <String>[];
    final queue = DailyReminderSyncQueue(({
      required enabled,
      required timeHhMm,
      required title,
      required body,
    }) async {
      calls.add('${enabled ? 'schedule' : 'cancel'}:$timeHhMm');
      if (enabled) {
        started.complete();
        return finishSchedule.future;
      }
      return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
    });

    final restoreRevision = queue.revision;
    final restore = queue.scheduleIfCurrent(
      revision: restoreRevision,
      enabled: true,
      timeHhMm: '07:35',
      title: '217',
      body: 'Record today',
    );
    await started.future;

    // A settings save starts while Android is still completing the old plan.
    final settingsRevision = queue.beginIntent();
    final settingsSave = queue.scheduleIfCurrent(
      revision: settingsRevision,
      enabled: false,
      timeHhMm: '07:35',
      title: '217',
      body: 'Record today',
    );
    finishSchedule.complete(
      const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled),
    );

    await Future.wait([restore, settingsSave]);
    expect(calls, ['schedule:07:35', 'cancel:07:35']);
  });

  test('intent invalidates a restore while its preference read is pending',
      () async {
    var schedules = 0;
    final queue = DailyReminderSyncQueue(({
      required enabled,
      required timeHhMm,
      required title,
      required body,
    }) async {
      schedules++;
      return const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled);
    });

    final restoreRevision = queue.revision;
    queue.beginIntent();
    final result = await queue.scheduleIfCurrent(
      revision: restoreRevision,
      enabled: true,
      timeHhMm: '09:00',
      title: '217',
      body: 'Record today',
    );

    expect(result, isNull);
    expect(schedules, 0);
  });

  test('queued safety cancellation survives a later read-only intent',
      () async {
    final started = Completer<void>();
    final finishSchedule = Completer<LocalReminderSyncResult>();
    final calls = <bool>[];
    final queue = DailyReminderSyncQueue(({
      required enabled,
      required timeHhMm,
      required title,
      required body,
    }) async {
      calls.add(enabled);
      if (enabled) {
        started.complete();
        return finishSchedule.future;
      }
      return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
    });

    final restore = queue.scheduleUserIntent(
      enabled: true,
      timeHhMm: '09:00',
      title: '217',
      body: 'Record today',
    );
    await started.future;
    final cancel = queue.cancel(title: '217', body: 'Record today');
    // A Settings preference read has a newer revision but no replacement OS
    // mutation until its response arrives.
    queue.beginIntent();
    finishSchedule.complete(
      const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled),
    );

    await Future.wait([restore, cancel]);
    expect(calls, [true, false]);
  });
}
