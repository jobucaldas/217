import 'local_reminders_stub.dart'
    if (dart.library.io) 'local_reminders_io.dart' as impl;

/// Schedules (or cancels) a daily local reminder when the platform supports it.
Future<bool> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) =>
    impl.syncLocalDailyReminder(
      enabled: enabled,
      timeHhMm: timeHhMm,
      title: title,
      body: body,
    );

/// True when this build can schedule OS local notifications (Android/iOS).
bool get supportsLocalReminders => impl.supportsLocalReminders;
