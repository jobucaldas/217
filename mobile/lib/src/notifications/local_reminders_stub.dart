/// Web / unsupported platforms — no local OS notifications.
bool get supportsLocalReminders => false;

Future<bool> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) async =>
    false;
