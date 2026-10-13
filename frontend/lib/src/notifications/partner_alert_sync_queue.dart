import 'local_reminders.dart';

typedef PartnerAlertScheduler = Future<LocalReminderSyncStatus> Function(
    List<PlannedAlert> alerts);

/// Serializes partner alert plans with safety cancellations across screens.
class PartnerAlertSyncQueue {
  PartnerAlertSyncQueue({
    required PartnerAlertScheduler scheduler,
    Future<void> Function()? canceller,
  })  : _scheduler = scheduler,
        _canceller = canceller;

  final PartnerAlertScheduler _scheduler;
  final Future<void> Function()? _canceller;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;

  int get revision => _revision;

  bool isCurrent(int revision) => revision == _revision;

  int beginIntent() => ++_revision;

  /// Calendar has just finished its data read and checked its load generation.
  Future<LocalReminderSyncStatus?> scheduleUserIntent(
    List<PlannedAlert> alerts,
  ) {
    final revision = beginIntent();
    return scheduleIfCurrent(revision: revision, alerts: alerts);
  }

  /// Replaces the queued plan when its read generation is still current.
  Future<LocalReminderSyncStatus?> scheduleIfCurrent({
    required int revision,
    required List<PlannedAlert> alerts,
  }) {
    return _enqueue(
      revision: revision,
      alerts: alerts,
    );
  }

  /// Settings may only apply a plan if no session/cancel/user change happened
  /// while its preference and calendar requests were in flight.
  /// Safety cleanup always runs in queue order, even if later reads begin.
  Future<LocalReminderSyncStatus?> cancel() {
    final revision = beginIntent();
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
  }) {
    final operation = _tail.then((_) async {
      if (!runEvenIfSuperseded && !isCurrent(revision)) return null;
      if (cancellation && _canceller != null) {
        await _canceller();
        return LocalReminderSyncStatus.cancelled;
      }
      return _scheduler(alerts);
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
