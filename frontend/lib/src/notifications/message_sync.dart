import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';
import 'local_reminders.dart';

typedef MessageNotifier = Future<bool> Function({
  required String title,
  required String body,
});

/// Announces [messages] received by [userId] after the newest one already
/// announced on this device, then moves that mark forward. Shared by the
/// foreground check and the background worker, so a message is announced
/// once whichever of them sees it first. The first check on a device only
/// sets the mark (no backlog alert).
Future<void> announceNewMessages({
  required AppearancePrefs prefs,
  required String userId,
  required List<InboxMessage> messages,
  required Strings strings,
  required bool notify,
  MessageNotifier show = showMessageNotification,
  Future<bool> Function()? stillAllowed,
}) async {
  final upTo = await prefs.messagesNotifiedUpTo(userId);
  if (notify && upTo != null) {
    final fresh = unannouncedMessages(messages, upTo);
    // Checked last, right before posting: the session or the toggle may
    // have changed while the inbox loaded.
    if (fresh.isNotEmpty && (stillAllowed == null || await stillAllowed())) {
      final text = messageNotificationText(strings, fresh);
      await show(title: text.title, body: text.body);
    }
  }
  // An empty first check still sets the starting point, so the first
  // message that arrives later is announced. The mark only moves forward.
  final newest = newestReceived(messages, upTo) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  if (newest != upTo) {
    await prefs.saveMessagesNotifiedUpTo(userId, newest);
  }
}
