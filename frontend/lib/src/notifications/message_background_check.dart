import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../config.dart';
import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';
import 'local_reminders.dart';
import 'message_sync.dart';

/// The app checks every 2 minutes while in the foreground; a mark older
/// than this means it was killed without pausing.
const foregroundCheckFresh = Duration(minutes: 5);

/// One background inbox check (the app may be closed): with notifications
/// on and a signed-in account that can message, announces messages that
/// arrived since the last announced one. Returns quietly without a session,
/// a role, consent or a linked calendar, and while the app itself is in the
/// foreground (it announces then).
///
/// Read-only on purpose: it uses the saved server and token as they were
/// when it started and never renews, saves or clears the session (that is
/// the app's job), so an expired session waits until 217 is opened.
/// Network errors propagate to the caller, which waits for the next run.
Future<void> checkMessagesInBackground({
  required AppConfig config,
  required http.Client client,
  required AppearancePrefs prefs,
  required AppLanguage deviceLanguage,
  FlutterSecureStorage storage = const FlutterSecureStorage(),
  MessageNotifier show = showMessageNotification,
  DateTime Function() now = DateTime.now,
}) async {
  if (!await prefs.messageNotificationsEnabled()) return;
  final foregroundAt = await prefs.messagesForegroundAt();
  if (foregroundAt != null &&
      now().difference(foregroundAt) < foregroundCheckFresh) {
    return;
  }
  // Every request of this run goes to this server with this token, even if
  // the user signs out or in (maybe elsewhere) meanwhile.
  final login = await ApiClient.storedLogin(config, storage);
  final token = login.token;
  if (login.server.isEmpty || token == null || token.isEmpty) return;

  Future<Map<String, dynamic>?> get(String path) async {
    final response = await client.get(
      Uri.parse('${login.server}$path'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  final sessionJson = await get('/api/auth/session');
  if (sessionJson == null) return;
  final session = SessionSnapshot.fromJson(sessionJson);
  final user = session.user;
  if (user == null || !user.hasRole || session.consentRequired) return;
  if (user.isPartner && !(session.share?.isActive ?? false)) return;

  final inboxJson = await get('/api/inbox');
  if (inboxJson == null) return;
  final messages = (inboxJson['notes'] as List<dynamic>? ?? const [])
      .map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
      .toList();
  final language = await prefs.loadLanguage() ?? deviceLanguage;
  await announceNewMessages(
    prefs: prefs,
    userId: user.id,
    messages: messages,
    strings: Strings(language),
    notify: true,
    show: show,
    // Checked right before posting: nothing shows for a session that was
    // signed out or replaced while the inbox loaded.
    stillAllowed: () async {
      final current = await ApiClient.storedLogin(config, storage);
      return current.token == token &&
          current.server == login.server &&
          await prefs.messageNotificationsEnabled();
    },
  );
}
