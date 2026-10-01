import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'intake_daily';
const _notifId = 21701;

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

bool get supportsLocalReminders =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<bool> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) async {
  if (!supportsLocalReminders) return false;
  try {
    await _ensureReady();
    if (!enabled) {
      await _plugin.cancel(_notifId);
      return true;
    }
    final parts = timeHhMm.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    const android = AndroidNotificationDetails(
      _channelId,
      'Daily intake',
      channelDescription: 'Reminder to log today’s intake',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    final when = _nextLocalAsUtc(hour, minute);
    await _plugin.zonedSchedule(
      _notifId,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> _ensureReady() async {
  if (_ready) return;
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.UTC);
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await _plugin.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  _ready = true;
}

/// Convert device-local wall time to a TZDateTime in UTC for scheduling.
tz.TZDateTime _nextLocalAsUtc(int hour, int minute) {
  final now = DateTime.now();
  var local = DateTime(now.year, now.month, now.day, hour, minute);
  if (!local.isAfter(now)) {
    local = local.add(const Duration(days: 1));
  }
  final utc = local.toUtc();
  return tz.TZDateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
  );
}
