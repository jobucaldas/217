import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'owner_reminder_repeat_plan.dart';
import 'partner_alert_plan.dart';
import 'reminder_schedule.dart';

const _channelId = 'intake_daily';
const _partnerChannelId = 'partner_alerts';
const _notifId = 21701;
const _messagesChannelId = 'messages';
const _messageNotifId = 21750;

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
  bool repeatEnabled = false,
  int repeatMinutes = 15,
  bool todayLogged = false,
}) async {
  if (!supportsLocalReminders) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
  }

  try {
    final ready = await _ensureReady(requestPermission: enabled);
    if (!ready) {
      return const LocalReminderSyncResult(
        LocalReminderSyncStatus.permissionDenied,
      );
    }

    if (!enabled) {
      await _plugin.cancel(_notifId);
      await _cancelOwnerReminderRepeats();
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

    // Repeat range cleared in full on every sync (idempotent replan), so a
    // logged pill or a disabled repeat drops any pending occurrence.
    await _cancelOwnerReminderRepeats();
    if (repeatEnabled) {
      final repeats = planOwnerReminderRepeat(
        now: DateTime.now(),
        enabled: enabled,
        repeatEnabled: repeatEnabled,
        repeatMinutes: repeatMinutes,
        timeHhMm: timeHhMm,
        todayLogged: todayLogged,
        title: title,
        body: body,
      );
      for (final repeat in repeats) {
        await _plugin.zonedSchedule(
          repeat.id,
          repeat.title,
          repeat.body,
          tz.TZDateTime.from(repeat.when, tz.local),
          details,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
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

Future<void> _cancelOwnerReminderRepeats() async {
  for (var i = 0; i < ownerReminderRepeatIdCount; i++) {
    await _plugin.cancel(ownerReminderRepeatIdBase + i);
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
    // Pill-repeat range: cleared in full on every sync (idempotent replan),
    // so a logged pill or a disabled repeat drops any pending occurrence.
    for (var i = 0; i < partnerPillRepeatIdCount; i++) {
      await _plugin.cancel(partnerPillRepeatIdBase + i);
    }
    if (alerts.isEmpty) return LocalReminderSyncStatus.cancelled;
    final exact = await _canUseExactAlarms();
    // Same high-importance, sound-on channel as the other partner alerts
    // makes the pill repeat alarm-like. Exact alarms fire on time but need
    // USE_EXACT_ALARM (Android 13+, auto-granted) or SCHEDULE_EXACT_ALARM
    // (Android 12 and below, user-granted); when neither is held we fall
    // back to inexact-while-idle, which Doze can delay by several minutes
    // per occurrence.
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

Future<bool> showMessageNotification({
  required String title,
  required String body,
}) async {
  if (!supportsLocalReminders) return false;
  try {
    await _ensureReady(requestPermission: false);
    // Private: the lock screen shows that a message came, not its text.
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _messagesChannelId,
        'Messages',
        channelDescription: 'New messages from your partner',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(_messageNotifId, title, body, details);
    return true;
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> requestNotificationPermission() async {
  if (!supportsLocalReminders) return false;
  try {
    await _ensureReady(requestPermission: false);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> cancelMessageNotification() async {
  if (!supportsLocalReminders) return;
  try {
    await _ensureReady(requestPermission: false);
    await _plugin.cancel(_messageNotifId);
  } catch (_) {}
}
