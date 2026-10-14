import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/notifications/partner_alert_sync_queue.dart';

void main() {
  test('newer intent drops a delayed alert plan', () async {
    final started = Completer<void>();
    final finishSchedule = Completer<LocalReminderSyncStatus>();
    final calls = <List<PlannedAlert>>[];
    final queue = PartnerAlertSyncQueue(scheduler: (alerts) {
      calls.add(alerts);
      if (alerts.isNotEmpty) {
        started.complete();
        return finishSchedule.future;
      }
      return Future.value(LocalReminderSyncStatus.cancelled);
    });
    final plan = [
      PlannedAlert(
        id: 21720,
        when: DateTime(2026, 10, 14),
        title: 'Reminder',
        body: 'Pill not logged',
      ),
    ];

    final oldPlan = queue.scheduleUserIntent(plan);
    await started.future;
    final newerRevision = queue.beginIntent();
    final newPlan = queue.scheduleIfCurrent(
      revision: newerRevision,
      alerts: const [],
    );
    finishSchedule.complete(LocalReminderSyncStatus.scheduled);

    await Future.wait([oldPlan, newPlan]);
    expect(calls, [plan, const <PlannedAlert>[]]);
  });

  test('cancellation runs after a pending plan and clears scheduled alerts',
      () async {
    final started = Completer<void>();
    final finishSchedule = Completer<LocalReminderSyncStatus>();
    final calls = <String>[];
    final queue = PartnerAlertSyncQueue(
      scheduler: (alerts) async {
        calls.add(alerts.isEmpty ? 'clear' : 'schedule');
        if (alerts.isNotEmpty) {
          started.complete();
          return finishSchedule.future;
        }
        return LocalReminderSyncStatus.cancelled;
      },
      canceller: () async => calls.add('cancel'),
    );

    final plan = queue.scheduleUserIntent([
      PlannedAlert(
        id: 21720,
        when: DateTime(2026, 10, 14),
        title: 'Reminder',
        body: 'Pill not logged',
      ),
    ]);
    await started.future;
    final cancellation = queue.cancel();
    finishSchedule.complete(LocalReminderSyncStatus.scheduled);

    await Future.wait([plan, cancellation]);
    expect(calls, ['schedule', 'cancel']);
  });

  test('logout cancellation invalidates a delayed background read', () async {
    final calls = <List<PlannedAlert>>[];
    final queue = PartnerAlertSyncQueue(scheduler: (alerts) async {
      calls.add(alerts);
      return LocalReminderSyncStatus.scheduled;
    });
    final readRevision = queue.revision;

    await queue.cancel();
    final result = await queue.scheduleBackgroundIfCurrent(
      revision: readRevision,
      alerts: [
        PlannedAlert(
          id: 21720,
          when: DateTime(2026, 10, 14),
          title: 'Reminder',
          body: 'Pill not logged',
        ),
      ],
    );

    expect(result, isNull);
    expect(calls, [const <PlannedAlert>[]]);
  });

  test('background planning cannot supersede a pending Settings save',
      () async {
    final calls = <List<PlannedAlert>>[];
    final queue = PartnerAlertSyncQueue(scheduler: (alerts) async {
      calls.add(alerts);
      return LocalReminderSyncStatus.scheduled;
    });
    final settingsRevision = queue.beginIntent();
    final oldEnabledPlan = [
      PlannedAlert(
        id: 21720,
        when: DateTime(2026, 10, 14),
        title: 'Reminder',
        body: 'Pill not logged',
      ),
    ];

    final backgroundResult = await queue.scheduleBackgroundIfCurrent(
      revision: queue.revision,
      alerts: oldEnabledPlan,
    );
    final settingsResult = await queue.scheduleIfCurrent(
      revision: settingsRevision,
      alerts: const [],
    );
    queue.finishIntent(settingsRevision);

    expect(backgroundResult, isNull);
    expect(settingsResult, LocalReminderSyncStatus.scheduled);
    expect(calls, [const <PlannedAlert>[]]);
  });
}
