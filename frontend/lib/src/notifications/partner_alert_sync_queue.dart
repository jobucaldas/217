import 'local_reminders.dart';

typedef PartnerAlertScheduler = Future<LocalReminderSyncStatus> Function(
    List<PlannedAlert> alerts);

/// Serializes partner alert plans with safety cancellations across screens.
class PartnerAlertSyncQueue {
  /// [permissionScheduler] runs plans marked `requestPermission` (explicit
  /// user actions, which may show the system permission prompt); it falls
  /// back to [scheduler].
  PartnerAlertSyncQueue({
    required PartnerAlertScheduler scheduler,
    PartnerAlertScheduler? permissionScheduler,
    Future<void> Function()? canceller,
  })  : _scheduler = scheduler,
        _permissionScheduler = permissionScheduler,
        _canceller = canceller;

  final PartnerAlertScheduler _scheduler;
  final PartnerAlertScheduler? _permissionScheduler;
  final Future<void> Function()? _canceller;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;
  int? _pendingUserRevision;

  int get revision => _revision;

  bool isCurrent(int revision) => revision == _revision;

  int beginIntent() {
    final revision = ++_revision;
    _pendingUserRevision = revision;
    return revision;
  }

  void finishIntent(int revision) {
    if (_pendingUserRevision == revision) _pendingUserRevision = null;
  }

  /// Applies a plan initiated by the user.
  Future<LocalReminderSyncStatus?> scheduleUserIntent(
    List<PlannedAlert> alerts, {
    bool requestPermission = false,
  }) {
    final revision = beginIntent();
    return scheduleIfCurrent(
      revision: revision,
      alerts: alerts,
      requestPermission: requestPermission,
    ).whenComplete(
      () => finishIntent(revision),
    );
  }

  /// Replaces the queued plan when its read generation is still current.
  /// [requestPermission] is for plans an explicit user action asked for.
  Future<LocalReminderSyncStatus?> scheduleIfCurrent({
    required int revision,
    required List<PlannedAlert> alerts,
    bool requestPermission = false,
  }) {
    return _enqueue(
      revision: revision,
      alerts: alerts,
      requestPermission: requestPermission,
    );
  }

  /// Background reads may update alerts only when no Settings write is pending.
  Future<LocalReminderSyncStatus?> scheduleBackgroundIfCurrent({
    required int revision,
    required List<PlannedAlert> alerts,
  }) =>
      _enqueue(
        revision: revision,
        alerts: alerts,
        background: true,
      );

  /// Settings may only apply a plan if no session/cancel/user change happened
  /// while its preference and calendar requests were in flight.
  /// Safety cleanup always runs in queue order, even if later reads begin.
  Future<LocalReminderSyncStatus?> cancel() {
    final revision = beginIntent();
    _pendingUserRevision = null;
    return _enqueue(
      revision: revision,
      alerts: const [],
      runEvenIfSuperseded: true,
      cancellation: true,
    );
  }

  Future<LocalReminderSyncStatus?> _enqueue({
    required int revision,
    required List<PlannedAlert> alerts,
    bool runEvenIfSuperseded = false,
    bool cancellation = false,
    bool background = false,
    bool requestPermission = false,
  }) {
    final operation = _tail.then((_) async {
      if (!runEvenIfSuperseded && !isCurrent(revision)) return null;
      if (background && _pendingUserRevision != null) return null;
      if (cancellation && _canceller != null) {
        await _canceller();
        return LocalReminderSyncStatus.cancelled;
      }
      final scheduler =
          (requestPermission ? _permissionScheduler : null) ?? _scheduler;
      return scheduler(alerts);
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
