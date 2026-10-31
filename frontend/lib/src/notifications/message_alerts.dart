import '../i18n.dart';
import '../models.dart';

/// Received, unread messages newer than [notifiedUpTo] (the newest message
/// already announced or seen), oldest first. Server timestamps only, so the
/// device clock does not matter.
List<InboxMessage> unannouncedMessages(
  List<InboxMessage> messages,
  DateTime? notifiedUpTo,
) {
  final fresh = messages
      .where((m) =>
          m.isUnread &&
          (notifiedUpTo == null || m.createdAt.isAfter(notifiedUpTo)))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return fresh;
}

/// Newest received message time, or [current] when nothing newer arrived.
DateTime? newestReceived(List<InboxMessage> messages, DateTime? current) {
  var newest = current;
  for (final m in messages) {
    if (m.fromMe) continue;
    if (newest == null || m.createdAt.isAfter(newest)) newest = m.createdAt;
  }
  return newest;
}

/// One notification for a batch: the latest body, or a count when several.
({String title, String body}) messageNotificationText(
  Strings strings,
  List<InboxMessage> fresh,
) {
  final last = fresh.last;
  return (
    title: strings.messageNotifTitle(last.fromLabel),
    body: fresh.length == 1
        ? last.body
        : strings.messageNotifManyBody(fresh.length),
  );
}
