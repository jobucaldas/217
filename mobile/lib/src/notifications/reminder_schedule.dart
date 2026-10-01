// Pure helpers for daily local reminder wall-clock scheduling.

({int hour, int minute}) parseReminderTime(String timeHhMm) {
  final parts = timeHhMm.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts.first : '') ?? 9;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return (
    hour: hour.clamp(0, 23),
    minute: minute.clamp(0, 59),
  );
}

/// Next device-local DateTime at [hour]:[minute] strictly after [now].
DateTime nextDailyOccurrence(DateTime now, int hour, int minute) {
  var next = DateTime(now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}

/// Outcome of trying to schedule or cancel a local daily reminder.
enum LocalReminderSyncStatus {
  /// Daily OS notification is scheduled (or was already scheduled).
  scheduled,

  /// Reminder disabled and any pending local notification cancelled.
  cancelled,

  /// Platform can do local notifications but the user denied permission.
  permissionDenied,

  /// This build cannot schedule OS local notifications (e.g. web without SW).
  unsupported,

  /// Plugin/OS call failed after permissions were granted.
  failed,
}

class LocalReminderSyncResult {
  const LocalReminderSyncResult(this.status, {this.exact = false});

  final LocalReminderSyncStatus status;
  final bool exact;

  bool get ok =>
      status == LocalReminderSyncStatus.scheduled ||
      status == LocalReminderSyncStatus.cancelled;

  bool get localDeliveryActive => status == LocalReminderSyncStatus.scheduled;
}
