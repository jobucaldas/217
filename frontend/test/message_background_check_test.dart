import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/notifications/message_background_check.dart';
import 'package:a217/src/prefs.dart';

void main() {
  var inbox = <Map<String, dynamic>>[];
  var requests = <String>[];
  var signOutDuringInbox = false;
  final client = MockClient((request) async {
    requests.add(request.url.path);
    if (request.url.path == '/api/inbox' && signOutDuringInbox) {
      await const FlutterSecureStorage().delete(key: 'session_token');
    }
    if (request.url.path == '/api/auth/session') {
      return http.Response(
        jsonEncode({
          'user': {'id': 'u1', 'email': 'p@x', 'role': 'partner'},
          'share': {'status': 'active'},
        }),
        200,
      );
    }
    return http.Response(jsonEncode({'notes': inbox}), 200);
  });
  final config = AppConfig(
    apiBaseUrl: 'https://217.example',
    workosClientId: '',
    redirectUri: 'com.caldasstudios.app217://auth/callback',
  );
  Map<String, dynamic> msg(String id, int minute) => {
        'id': id,
        'body': 'hi $id',
        'from_name': 'Ana',
        'created_at': DateTime.utc(2026, 10, 31, 12, minute).toIso8601String(),
      };

  setUp(() {
    inbox = [];
    requests = [];
    signOutDuringInbox = false;
  });

  test('announces each new message once, after a silent first run', () async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 't'});
    final shown = <String>[];
    Future<void> run() => checkMessagesInBackground(
          config: config,
          client: client,
          prefs: AppearancePrefs(),
          deviceLanguage: AppLanguage.en,
          show: ({required title, required body}) async {
            shown.add('$title: $body');
            return true;
          },
        );

    inbox = [msg('a', 1)];
    await run(); // first run on this device: sets the mark only
    expect(shown, isEmpty);
    inbox = [msg('a', 1), msg('b', 2)];
    await run();
    await run();
    expect(shown, ['New message from Ana: hi b']);
  });

  test('does nothing when turned off or signed out', () async {
    Future<void> run() => checkMessagesInBackground(
          config: config,
          client: client,
          prefs: AppearancePrefs(),
          deviceLanguage: AppLanguage.en,
          show: ({required title, required body}) async => true,
        );
    FlutterSecureStorage.setMockInitialValues(
        {'session_token': 't', AppearancePrefs.messageNotificationsKey: '0'});
    await run();
    FlutterSecureStorage.setMockInitialValues({});
    await run();
    expect(requests, isEmpty);
  });

  test('skips while the app is in the foreground, or signed out meanwhile',
      () async {
    final shown = <String>[];
    Future<void> run() => checkMessagesInBackground(
          config: config,
          client: client,
          prefs: AppearancePrefs(),
          deviceLanguage: AppLanguage.en,
          show: ({required title, required body}) async {
            shown.add(body);
            return true;
          },
        );
    FlutterSecureStorage.setMockInitialValues({
      'session_token': 't',
      '${AppearancePrefs.messagesNotifiedKeyPrefix}u1': '2026-10-31T12:00:00Z',
      AppearancePrefs.messagesForegroundAtKey:
          DateTime.now().toUtc().toIso8601String(),
    });
    inbox = [msg('a', 1)];
    await run();
    expect(requests, isEmpty);

    await AppearancePrefs().saveMessagesForegroundAt(null);
    signOutDuringInbox = true;
    await run();
    expect(requests, ['/api/auth/session', '/api/inbox']);
    expect(shown, isEmpty);
  });
}
