import 'local_reminders.dart';

typedef DailyReminderScheduler = Future<LocalReminderSyncResult> Function({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
  bool repeatEnabled,
  int repeatMinutes,
  bool todayLogged,
});

/// Serializes local daily reminder operations and invalidates stale restores.
class DailyReminderSyncQueue {
  /// [permissionScheduler] runs operations marked `requestPermission`
  /// (explicit user actions, which may show the system permission prompt);
  /// it falls back to [_scheduler].
  DailyReminderSyncQueue(
    this._scheduler, {
    DailyReminderScheduler? permissionScheduler,
  }) : _permissionScheduler = permissionScheduler;

  final DailyReminderScheduler _scheduler;
  final DailyReminderScheduler? _permissionScheduler;
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
    bool repeatEnabled = false,
    int repeatMinutes = 15,
    bool todayLogged = false,
    bool requestPermission = false,
  }) {
    final revision = beginIntent();
    return _enqueue(
      revision: revision,
      enabled: enabled,
      timeHhMm: timeHhMm,
      title: title,
      body: body,
      repeatEnabled: repeatEnabled,
      repeatMinutes: repeatMinutes,
      todayLogged: todayLogged,
      requestPermission: requestPermission,
    );
  }

  /// Schedule a value read asynchronously only if no newer intent appeared.
  /// [requestPermission] is for operations an explicit user action asked for.
  Future<LocalReminderSyncResult?> scheduleIfCurrent({
    required int revision,
    required bool enabled,
    required String timeHhMm,
    required String title,
    required String body,
    bool repeatEnabled = false,
    int repeatMinutes = 15,
    bool todayLogged = false,
    bool requestPermission = false,
  }) =>
      _enqueue(
        revision: revision,
        enabled: enabled,
        timeHhMm: timeHhMm,
        title: title,
        body: body,
        repeatEnabled: repeatEnabled,
        repeatMinutes: repeatMinutes,
        todayLogged: todayLogged,
        requestPermission: requestPermission,
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
    bool repeatEnabled = false,
    int repeatMinutes = 15,
    bool todayLogged = false,
    bool runEvenIfSuperseded = false,
    bool requestPermission = false,
  }) {
    final operation = _tail.then((_) async {
      if (!runEvenIfSuperseded && !isCurrent(revision)) return null;
      final scheduler =
          (requestPermission ? _permissionScheduler : null) ?? _scheduler;
      return scheduler(
        enabled: enabled,
        timeHhMm: timeHhMm,
        title: title,
        body: body,
        repeatEnabled: repeatEnabled,
        repeatMinutes: repeatMinutes,
        todayLogged: todayLogged,
      );
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
