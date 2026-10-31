import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/message_alerts.dart';

InboxMessage _msg(String id, int minute,
        {bool mine = false, bool read = false}) =>
    InboxMessage(
      id: id,
      body: 'body $id',
      createdAt: DateTime.utc(2026, 10, 31, 12, minute),
      fromName: mine ? 'Me' : 'Ana',
      fromMe: mine,
      readAt: read ? DateTime.utc(2026, 10, 31, 13) : null,
    );

void main() {
  final messages = [
    _msg('d', 4),
    _msg('c', 3, mine: true),
    _msg('b', 2),
    _msg('a', 1, read: true),
  ];

  test('only unread received messages after the marker are announced', () {
    final upTo = DateTime.utc(2026, 10, 31, 12, 1);
    expect(unannouncedMessages(messages, upTo).map((m) => m.id), ['b', 'd']);
    // Once the marker moves to the newest received one, nothing repeats.
    final next = newestReceived(messages, upTo);
    expect(next, DateTime.utc(2026, 10, 31, 12, 4));
    expect(unannouncedMessages(messages, next), isEmpty);
  });

  test('one notification per batch', () {
    const strings = Strings(AppLanguage.en);
    final one = messageNotificationText(strings, [_msg('b', 2)]);
    expect(one.title, 'New message from Ana');
    expect(one.body, 'body b');
    final many = messageNotificationText(strings, [_msg('b', 2), _msg('d', 4)]);
    expect(many.body, '2 new messages');
  });
}
