import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/offline/local_store_memory.dart';

void main() {
  late List<http.Request> requests;
  late http.Response Function() answer;
  late ApiClient api;
  var consentRequired = 0;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'session_token': 't'});
    requests = [];
    consentRequired = 0;
    answer = () => http.Response('{}', 404);
    api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://api.example',
        workosClientId: 'client',
        redirectUri: 'com.caldasstudios.app217://auth/callback',
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        return answer();
      }),
      localStore: MemoryLocalStore(),
    )..onConsentRequired = () => consentRequired++;
  });

  test('sends the ETag as If-None-Match, and none without one', () async {
    await api.syncStatus();
    await api.syncStatus(etag: '');
    await api.syncStatus(etag: 'abc');
    expect(requests.map((r) => r.url.path), everyElement('/api/sync/status'));
    expect(requests.map((r) => r.headers['If-None-Match']),
        [null, null, '"abc"']);
    expect(requests.first.headers['Authorization'], 'Bearer t');
  });

  test('304 is not modified', () async {
    answer = () => http.Response('', 304, headers: {'etag': '"abc"'});
    final result = await api.syncStatus(etag: 'abc');
    expect(result.kind, SyncStatusKind.notModified);
    expect(result.notModified, isTrue);
    expect(result.status, isNull);
  });

  test('200 carries the status and tags', () async {
    answer = () => http.Response(
          jsonEncode({
            'etag': 'e2',
            'user_id': 'u1',
            'role': 'partner',
            'share_active': true,
            'subject_consent': true,
            'tags': {
              'account': 'a',
              'inbox': 'i',
              'calendar': 'c',
              'prefs': 'p',
            },
          }),
          200,
        );
    final result = await api.syncStatus(etag: 'e1');
    expect(result.kind, SyncStatusKind.changed);
    final status = result.status!;
    expect(status.etag, 'e2');
    expect(status.userId, 'u1');
    expect(status.role, 'partner');
    expect(status.shareActive, isTrue);
    expect(status.subjectConsent, isTrue);
    expect(status.tags.inbox, 'i');
    expect(status.tags.calendar, 'c');
    expect(status.tags.prefs, 'p');
    expect(status.tags.account, 'a');
  });

  test('404 means an older server', () async {
    final result = await api.syncStatus();
    expect(result.kind, SyncStatusKind.unsupported);
    expect(result.unsupported, isTrue);
  });

  test('403 consent required reaches the consent hook and throws', () async {
    answer = () => http.Response('{"error":"consent required"}', 403);
    await expectLater(api.syncStatus(), throwsA(isA<ApiException>()));
    expect(consentRequired, 1);
  });
}
