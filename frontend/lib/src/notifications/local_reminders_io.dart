import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'partner_alert_plan.dart';
import 'reminder_schedule.dart';

const _channelId = 'intake_daily';
const _partnerChannelId = 'partner_alerts';
const _notifId = 21701;

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();
bool _initialized = false;

bool get supportsLocalReminders =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<LocalReminderSyncResult> syncLocalDailyReminder({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
}) async {
  if (!supportsLocalReminders) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
  }

  try {
    final ready = await _ensureReady();
    if (!ready) {
      return const LocalReminderSyncResult(
        LocalReminderSyncStatus.permissionDenied,
      );
    }

    if (!enabled) {
      await _plugin.cancel(_notifId);
      return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
    }

    final parsed = parseReminderTime(timeHhMm);
    final when = _nextTz(parsed.hour, parsed.minute);
    final exact = await _canUseExactAlarms();

    const android = AndroidNotificationDetails(
      _channelId,
      'Daily intake',
      channelDescription: 'Reminder to log today’s intake',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.zonedSchedule(
      _notifId,
      title,
      body,
      when,
      details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return LocalReminderSyncResult(
      LocalReminderSyncStatus.scheduled,
      exact: exact,
    );
  } on MissingPluginException {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
  } catch (_) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.failed);
  }
}

Future<bool> _ensureReady({bool requestPermission = true}) async {
  if (!_initialized) {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fall back to UTC location with wall-clock conversion below.
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;
  }
  if (!requestPermission) return true;

  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    final allowed = await android.requestNotificationsPermission();
    if (allowed == false) {
      return false;
    }
    // Best-effort exact alarms (Android 12+). Denial → inexact schedule.
    try {
      await android.requestExactAlarmsPermission();
    } catch (_) {}
  }

  final ios = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  if (ios != null) {
    final allowed = await ios.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (allowed == false) {
      return false;
    }
  }

  return true;
}

Future<bool> _canUseExactAlarms() async {
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return false;
  try {
    return await android.canScheduleExactNotifications() ?? false;
  } catch (_) {
    return false;
  }
}

tz.TZDateTime _nextTz(int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

Future<LocalReminderSyncStatus> syncPartnerAlerts(
  List<PlannedAlert> alerts,
) async {
  if (!supportsLocalReminders) return LocalReminderSyncStatus.unsupported;
  try {
    // Clearing alerts must not prompt for notification permission.
    if (!await _ensureReady(requestPermission: alerts.isNotEmpty)) {
      return LocalReminderSyncStatus.permissionDenied;
    }
    for (final base in [partnerPmsIdBase, partnerPillIdBase]) {
      for (var i = 0; i < partnerAlertIdCount; i++) {
        await _plugin.cancel(base + i);
      }
    }
    if (alerts.isEmpty) return LocalReminderSyncStatus.cancelled;
    final exact = await _canUseExactAlarms();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _partnerChannelId,
        'Partner alerts',
        channelDescription: 'PMS heads-up and pill not logged',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    for (final alert in alerts) {
      await _plugin.zonedSchedule(
        alert.id,
        alert.title,
        alert.body,
        tz.TZDateTime.from(alert.when, tz.local),
        details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    return LocalReminderSyncStatus.scheduled;
  } on MissingPluginException {
    return LocalReminderSyncStatus.unsupported;
  } catch (_) {
    return LocalReminderSyncStatus.failed;
  }
}
