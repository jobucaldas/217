import '../api/client.dart';
import '../i18n.dart';
import '../prefs.dart';
import 'local_reminders.dart';
import 'message_sync.dart';

/// One background inbox check (the app may be closed): with notifications
/// on and a signed-in account that can message, announces messages that
/// arrived since the last announced one. Returns quietly without a session,
/// a role, consent or a linked calendar. Network errors propagate to the
/// caller, which simply waits for the next run.
Future<void> checkMessagesInBackground({
  required ApiClient api,
  required AppearancePrefs prefs,
  required AppLanguage deviceLanguage,
  MessageNotifier show = showMessageNotification,
}) async {
  if (!await prefs.messageNotificationsEnabled()) return;
  await api.loadPersistedApiBase();
  if (api.config.needsServerSetup) return;
  final token = await api.readSessionToken();
  if (token == null || token.isEmpty) return;

  final session = await api.currentSession();
  final user = session.user;
  if (user == null || !user.hasRole || session.consentRequired) return;
  if (user.isPartner && !(session.share?.isActive ?? false)) return;

  final messages = await api.listInbox();
  final language = await prefs.loadLanguage() ?? deviceLanguage;
  await announceNewMessages(
    prefs: prefs,
    userId: user.id,
    messages: messages,
    strings: Strings(language),
    notify: true,
    show: show,
  );
}
