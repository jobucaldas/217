import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../config.dart';
import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';
import '../secure_storage.dart';
import 'local_reminders.dart';
import 'message_sync.dart';
import 'message_worker.dart';
import 'partner_alert_sync.dart';
import 'partner_alert_sync_queue.dart';

/// The app checks every 2 minutes while in the foreground; a mark older
/// than this means it was killed without pausing.
const foregroundCheckFresh = Duration(minutes: 5);

Future<LocalReminderSyncStatus> _scheduleWithoutPrompt(
  List<PlannedAlert> alerts,
) =>
    syncPartnerAlerts(alerts, requestPermission: false);

Future<void> _cancelWorker() => syncMessageWorker(enabled: false);

/// One background check (the app may be closed). One cheap
/// `GET /api/sync/status` with the saved ETag first: a 304 means nothing
/// changed and nothing else is requested. Otherwise only what changed is
/// read: the inbox (new messages are announced, with notifications on) and,
/// for a partner, today's entry, the cycle and the alert settings, from which
/// the local alerts are replanned (and a quiet note replaces a pill-not-logged
/// alert that was showing once the pill is logged). Older servers without the
/// endpoint get the previous inbox check.
///
/// Returns quietly without a session (and then removes the worker), and while
/// the app itself is in the foreground (it does all of this then).
///
/// Read-only on purpose: it uses the saved server and token as they were
/// when it started and never renews, saves or clears the session (that is
/// the app's job), so an expired session waits until 217 is opened. The
/// saved ETag moves forward only when everything it triggered succeeded, so
/// a failed read is retried by the next run. Network errors in the status
/// call propagate to the caller, which waits for the next run.
Future<void> checkMessagesInBackground({
  required AppConfig config,
  required http.Client client,
  required AppearancePrefs prefs,
  required AppLanguage deviceLanguage,
  FlutterSecureStorage storage = appSecureStorage,
  MessageNotifier show = showMessageNotification,
  DateTime Function() now = DateTime.now,
  PartnerAlertScheduler schedulePartnerAlerts = _scheduleWithoutPrompt,
  Future<bool> Function() hasActiveNag = hasActivePartnerPillAlert,
  MessageNotifier showClosure = showPartnerPillTakenClosure,
  Future<void> Function(DateTime? at) schedulePrecheck = schedulePartnerPrecheck,
  Future<void> Function() cancelWorker = _cancelWorker,
}) async {
  final foregroundAt = await prefs.messagesForegroundAt();
  if (foregroundAt != null &&
      now().difference(foregroundAt) < foregroundCheckFresh) {
    return;
  }
  // Every request of this run goes to this server with this token, even if
  // the user signs out or in (maybe elsewhere) meanwhile.
  final login = await ApiClient.storedLogin(config, storage);
  final token = login.token;
  if (login.server.isEmpty || token == null || token.isEmpty) {
    // Signed out: nothing left to check for.
    await cancelWorker();
    return;
  }
  final messagesOn = await prefs.messageNotificationsEnabled();
  final saved = await prefs.syncState();
  final baseline =
      saved != null && saved.server == login.server ? saved.status : null;
  // Nothing to look for: messages are off and no partner alert is known to
  // be on, so not even the status call is made.
  final partnerOn =
      await prefs.hasPartnerAlertsForWorker(userId: baseline?.userId);
  if (!messagesOn && !partnerOn) {
    return;
  }

  Future<http.Response> send(String path, {String? etag}) => client.get(
        Uri.parse('${login.server}$path'),
        headers: {
          'Authorization': 'Bearer $token',
          if (etag != null && etag.isNotEmpty) 'If-None-Match': '"$etag"',
        },
      ).timeout(const Duration(seconds: 20));

  Future<Map<String, dynamic>?> getJson(String path) async {
    final response = await send(path);
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // Checked right before posting or touching alarms: nothing happens for a
  // session that was signed out or replaced, or an app that came to the
  // foreground (it does this itself), while the reads were in flight.
  Future<bool> stillCurrent() async {
    final current = await ApiClient.storedLogin(config, storage);
    if (current.token != token || current.server != login.server) return false;
    final at = await prefs.messagesForegroundAt();
    return at == null || now().difference(at) >= foregroundCheckFresh;
  }

  Future<void> announce(String userId, List<InboxMessage> messages) async {
    final language = await prefs.loadLanguage() ?? deviceLanguage;
    await announceNewMessages(
      prefs: prefs,
      userId: userId,
      messages: messages,
      strings: Strings(language),
      notify: true,
      show: show,
      stillAllowed: () async =>
          await stillCurrent() && await prefs.messageNotificationsEnabled(),
    );
  }

  Future<bool> cancelPartnerAlerts() async {
    if (!await stillCurrent()) return false;
    final res = await schedulePartnerAlerts(const []);
    if (res == LocalReminderSyncStatus.failed) return false;
    await schedulePrecheck(null);
    return true;
  }

  final response = await send('/api/sync/status', etag: baseline?.etag);
  switch (response.statusCode) {
    case 304:
      // Even when nothing changed on the server, a new local day needs one
      // replan to keep the rolling pill-alert horizon and pre-check fresh.
      if (baseline != null &&
          baseline.role == 'partner' &&
          baseline.shareActive &&
          baseline.subjectConsent &&
          await prefs.partnerAlertsEnabled(baseline.userId)) {
        final today = DateFormat('yyyy-MM-dd').format(now());
        if (await prefs.partnerLastPlanDate(baseline.userId) != today) {
          try {
            await _replanPartnerAlerts(
              status: baseline,
              now: now,
              prefs: prefs,
              deviceLanguage: deviceLanguage,
              getResponse: send,
              stillCurrent: stillCurrent,
              schedulePartnerAlerts: schedulePartnerAlerts,
              hasActiveNag: hasActiveNag,
              showClosure: showClosure,
              schedulePrecheck: schedulePrecheck,
            );
          } catch (_) {}
        }
      }
      return; // nothing changed
    case 403:
      // Consent withdrawn or changed: a partner's alerts must not go on.
      if (baseline?.role == 'partner') await cancelPartnerAlerts();
      return;
    case 404:
      if (messagesOn) await _legacyInboxCheck(getJson, announce);
      return;
    case 200:
      break;
    default:
      return; // 401 (the app renews on open) or a server error: next run
  }

  final status =
      SyncStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  // A baseline of another account says nothing about this one.
  final base = baseline != null && baseline.userId == status.userId
      ? baseline
      : null;
  bool changed(String Function(SyncTags tags) tag) =>
      base == null || tag(status.tags) != tag(base.tags);
  final inboxChanged = changed((t) => t.inbox);
  final partnerChanged = changed((t) => t.calendar) ||
      changed((t) => t.prefs) ||
      changed((t) => t.account);
  var allSucceeded = true;

  if (inboxChanged &&
      messagesOn &&
      status.role.isNotEmpty &&
      (status.role == 'owner' || status.shareActive)) {
    try {
      final inbox = await getJson('/api/inbox');
      if (inbox == null) {
        allSucceeded = false;
      } else {
        await announce(
          status.userId,
          (inbox['notes'] as List<dynamic>? ?? const [])
              .map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      }
    } catch (_) {
      allSucceeded = false;
    }
  }

  if (status.role == 'partner') {
    if (!status.shareActive || !status.subjectConsent) {
      if (!status.shareActive && await stillCurrent()) {
        await prefs.savePartnerOwnerName(status.userId, '');
      }
      if (!await cancelPartnerAlerts()) allSucceeded = false;
    } else {
      final today = DateFormat('yyyy-MM-dd').format(now());
      final needsDailyReplan = !partnerChanged &&
          await prefs.partnerAlertsEnabled(status.userId) &&
          await prefs.partnerLastPlanDate(status.userId) != today;
      if (partnerChanged || needsDailyReplan) {
        try {
          allSucceeded &= await _replanPartnerAlerts(
            status: status,
            now: now,
            prefs: prefs,
            deviceLanguage: deviceLanguage,
            getResponse: send,
            stillCurrent: stillCurrent,
            schedulePartnerAlerts: schedulePartnerAlerts,
            hasActiveNag: hasActiveNag,
            showClosure: showClosure,
            schedulePrecheck: schedulePrecheck,
          );
        } catch (_) {
          allSucceeded = false;
        }
      }
    }
  }

  if (allSucceeded && await stillCurrent()) {
    await prefs.saveSyncState(login.server, status);
  }
}

/// Previous behaviour for servers without `/api/sync/status`: the session,
/// then the inbox.
Future<void> _legacyInboxCheck(
  Future<Map<String, dynamic>?> Function(String path) getJson,
  Future<void> Function(String userId, List<InboxMessage> messages) announce,
) async {
  final sessionJson = await getJson('/api/auth/session');
  if (sessionJson == null) return;
  final session = SessionSnapshot.fromJson(sessionJson);
  final user = session.user;
  if (user == null || !user.hasRole || session.consentRequired) return;
  if (user.isPartner && !(session.share?.isActive ?? false)) return;

  final inboxJson = await getJson('/api/inbox');
  if (inboxJson == null) return;
  await announce(
    user.id,
    (inboxJson['notes'] as List<dynamic>? ?? const [])
        .map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Reads today's entry, the cycle and the alert settings, and replans the
/// partner's local alerts from them. Returns false when a read or scheduler
/// call failed (nothing is acknowledged then, so the next run tries again).
Future<bool> _replanPartnerAlerts({
  required SyncStatus status,
  required DateTime Function() now,
  required AppearancePrefs prefs,
  required AppLanguage deviceLanguage,
  required Future<http.Response> Function(String path, {String? etag})
      getResponse,
  required Future<bool> Function() stillCurrent,
  required PartnerAlertScheduler schedulePartnerAlerts,
  required Future<bool> Function() hasActiveNag,
  required MessageNotifier showClosure,
  required Future<void> Function(DateTime? at) schedulePrecheck,
}) async {
  final at = now();
  final today = DateFormat('yyyy-MM-dd').format(at);
  final responses = await Future.wait([
    getResponse('/api/entries/$today'),
    getResponse('/api/cycle?today=$today'),
    getResponse('/api/partner-alerts'),
  ]);
  final entry = responses[0];
  final cycle = responses[1];
  final alerts = responses[2];
  // No entry for today is a day not logged; any other answer is no answer.
  if ((entry.statusCode != 200 && entry.statusCode != 404) ||
      cycle.statusCode != 200 ||
      alerts.statusCode != 200) {
    return false;
  }
  final todayLogged = entry.statusCode == 200 &&
      Entry.fromJson(jsonDecode(entry.body) as Map<String, dynamic>).taken ==
          true;
  final pref = PartnerAlertPreference.fromJson(
      jsonDecode(alerts.body) as Map<String, dynamic>);

  if (!await stillCurrent()) return false;
  // Before replanning: cancelling the alerts also clears one that is showing.
  final wasNagShowing = todayLogged && await hasActiveNag();

  if (!pref.pmsEnabled && !pref.pillEnabled) {
    final res = await schedulePartnerAlerts(const []);
    if (res == LocalReminderSyncStatus.failed) return false;
    await prefs.savePartnerAlertsEnabled(status.userId, false);
    await schedulePrecheck(null);
    return true;
  }
  await prefs.savePartnerAlertsEnabled(status.userId, true);
  final language = await prefs.loadLanguage() ?? deviceLanguage;
  final strings = Strings(language);
  final ownerName = await prefs.partnerOwnerName(status.userId);
  final syncStatus = await syncPartnerAlertsFrom(
    strings: strings,
    pref: pref,
    cycle: CycleInfo.fromJson(jsonDecode(cycle.body) as Map<String, dynamic>),
    linked: true,
    todayLogged: todayLogged,
    ownerName: ownerName,
    scheduler: schedulePartnerAlerts,
    now: at,
  );
  if (syncStatus == LocalReminderSyncStatus.failed) {
    return false;
  }
  if (!await stillCurrent()) return false;
  await prefs.savePartnerLastPlanDate(status.userId, today);
  if (wasNagShowing) {
    await showClosure(
      title: '217',
      body: strings.pillLoggedClosureBody(ownerName),
    );
  }
  await schedulePrecheck(partnerPrecheckAt(at, pref, todayLogged));
  return true;
}
