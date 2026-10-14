import 'local_reminders.dart';

typedef DailyReminderScheduler = Future<LocalReminderSyncResult> Function({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
});

/// Serializes local daily reminder operations and invalidates stale restores.
class DailyReminderSyncQueue {
  DailyReminderSyncQueue(this._scheduler);

  final DailyReminderScheduler _scheduler;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;

  int get revision => _revision;

  Future<void> get whenIdle => _tail;

  bool isCurrent(int revision) => revision == _revision;

  /// Records user intent before any network or preference read can yield.
  int beginIntent() => ++_revision;

  /// A settings operation is a newer intent, even while an older call is
  /// waiting for the OS permission sheet or alarm scheduler.
  Future<LocalReminderSyncResult?> scheduleUserIntent({
    required bool enabled,
    required String timeHhMm,
    required String title,
    required String body,
  }) {
    final revision = beginIntent();
    return _enqueue(
      revision: revision,
      enabled: enabled,
      timeHhMm: timeHhMm,
      title: title,
      body: body,
    );
  }

  /// Schedule a value read asynchronously only if no newer intent appeared.
  Future<LocalReminderSyncResult?> scheduleIfCurrent({
    required int revision,
    required bool enabled,
    required String timeHhMm,
    required String title,
    required String body,
  }) =>
      _enqueue(
        revision: revision,
        enabled: enabled,
        timeHhMm: timeHhMm,
        title: title,
        body: body,
      );

  /// Consent, logout, or account changes invalidate pending restores first.
  Future<LocalReminderSyncResult?> cancel({
    required String title,
    required String body,
  }) {
    final revision = beginIntent();
    return _enqueue(
      revision: revision,
      enabled: false,
      timeHhMm: '09:00',
      title: title,
      body: body,
      runEvenIfSuperseded: true,
    );
  }

  Future<LocalReminderSyncResult?> _enqueue({
    required int revision,
    required bool enabled,
    required String timeHhMm,
    required String title,
    required String body,
    bool runEvenIfSuperseded = false,
  }) {
    final operation = _tail.then((_) async {
      if (!runEvenIfSuperseded && !isCurrent(revision)) return null;
      return _scheduler(
        enabled: enabled,
        timeHhMm: timeHhMm,
        title: title,
        body: body,
      );
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
