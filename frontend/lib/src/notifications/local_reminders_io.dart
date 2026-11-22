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
const _partnerStatusChannelId = 'partner_status';
const _partnerPillTakenNotifId = 21730;
const _partnerPillTakenTimeoutMs = 2 * 60 * 60 * 1000;

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
  bool requestPermission = false,
}) async {
  if (!supportsLocalReminders) {
    return const LocalReminderSyncResult(LocalReminderSyncStatus.unsupported);
  }

  try {
    await _initialize();
    // Cancelling needs neither permission nor an Activity, so it always
    // runs first: a denied permission must not leave old repeats behind.
    // (Repeats are replanned in full below.)
    await _cancelOwnerReminderRepeats();
    if (!enabled) {
      await _plugin.cancel(_notifId);
      return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
    }

    final ready = await _ensureReady(requestPermission: requestPermission);
    if (!ready) {
      return const LocalReminderSyncResult(
        LocalReminderSyncStatus.permissionDenied,
      );
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

Future<void> _initialize() async {
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
}

/// Whether notifications can be shown. With [requestPermission] it may ask
/// (needs an Activity: explicit user actions only). Without, it only checks:
/// the background worker runs headless, where asking would crash.
Future<bool> _ensureReady({required bool requestPermission}) async {
  await _initialize();
  if (!requestPermission) {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      // Only an explicit "off" counts as denied; unknown stays allowed.
      return await android?.areNotificationsEnabled() != false;
    } catch (_) {
      return true;
    }
  }

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
  List<PlannedAlert> alerts, {
  bool requestPermission = false,
}) async {
  if (!supportsLocalReminders) return LocalReminderSyncStatus.unsupported;
  try {
    await _initialize();
    // Cancelling needs neither permission nor an Activity (the background
    // worker has none), so it always runs first, permission or not.
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
    if (alerts.isEmpty) {
      // Nothing of a partner session may outlive it, the quiet note included.
      await _plugin.cancel(_partnerPillTakenNotifId);
      return LocalReminderSyncStatus.cancelled;
    }
    if (!await _ensureReady(requestPermission: requestPermission)) {
      return LocalReminderSyncStatus.permissionDenied;
    }
    final exact = await _canUseExactAlarms();
    // Same high-importance, sound-on channel as the other partner alerts
    // makes the pill repeat alarm-like. Exact alarms fire on time but need
    // SCHEDULE_EXACT_ALARM, which the user grants in system settings (Android
    // 14+ denies it by default; USE_EXACT_ALARM is not declared because Google
    // Play reserves it for alarm-clock and calendar apps). Without it we fall
    // back to inexact-while-idle, which Doze can delay by several minutes
    // per occurrence.
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _partnerChannelId,
        'Partner alerts',
        channelDescription: 'PMS heads-up and pill not logged',
        importance: Importance.high,
        priority: Priority.high,
        // Private: the lock screen shows that an alert came, not its text.
        visibility: NotificationVisibility.private,
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

/// Whether today's pill-not-logged alert or one of its repeats is in the
/// tray: ids [partnerPillIdBase] and the first day's repeat block.
Future<bool> hasActivePartnerPillAlert() async {
  if (!supportsLocalReminders) return false;
  try {
    await _initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    for (final active in await android.getActiveNotifications()) {
      final id = active.id;
      if (id == null) continue;
      if (id == partnerPillIdBase ||
          (id >= partnerPillRepeatIdBase &&
              id < partnerPillRepeatIdBase + maxPillRepeatsPerDay)) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// One silent, low-importance note that expires on its own, replacing a
/// pill-not-logged alert that was showing. Private on the lock screen.
Future<bool> showPartnerPillTakenClosure({
  required String title,
  required String body,
}) async {
  if (!supportsLocalReminders) return false;
  try {
    await _ensureReady(requestPermission: false);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _partnerStatusChannelId,
        'Partner status',
        channelDescription: 'Quiet note once the pill is logged',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.private,
        timeoutAfter: _partnerPillTakenTimeoutMs,
      ),
      iOS: DarwinNotificationDetails(presentSound: false),
    );
    await _plugin.show(_partnerPillTakenNotifId, title, body, details);
    return true;
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
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
