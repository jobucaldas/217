import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/auth/device_key.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/offline/local_store_memory.dart';

class _FakeDeviceKey extends DeviceKey {
  final signed = <String>[];
  bool deleted = false;

  @override
  Future<String?> sign(String message) async {
    signed.add(message);
    return base64Encode(utf8.encode('sig'));
  }

  @override
  Future<void> delete() async => deleted = true;
}

const _user = {
  'id': 'u1',
  'email': 'owner@example.com',
  'name': 'Owner',
  'role': 'owner',
};

/// Server double: [up] false drops every request like a lost connection.
class _Server {
  bool up = true;
  String validToken = 'fresh';
  final entries = <String, Map<String, dynamic>>{};
  final requests = <String>[];
  int refuseWritesWith = 0;
  bool deviceRevoked = false;

  late final client = MockClient((req) async {
    if (!up) throw http.ClientException('offline');
    requests.add('${req.method} ${req.url.path}');
    final authed = req.headers['Authorization'] == 'Bearer $validToken';
    switch ((req.method, req.url.path)) {
      case ('GET', '/api/auth/session'):
        return _json({'user': authed ? _user : null, 'share': null});
      case ('POST', '/api/auth/device/challenge'):
        if (deviceRevoked) {
          return http.Response('{"error":"device not recognized"}', 401);
        }
        return _json({'challenge': 'c1'});
      case ('POST', '/api/auth/device/session'):
        return _json({'user': _user, 'session_token': validToken});
      case ('GET', '/api/entries'):
        if (!authed) return http.Response('{"error":"unauthorized"}', 401);
        return _json({'entries': entries.values.toList()});
    }
    if (req.url.path.startsWith('/api/entries/')) {
      if (!authed) return http.Response('{"error":"unauthorized"}', 401);
      if (refuseWritesWith != 0) {
        return http.Response('{"error":"bad"}', refuseWritesWith);
      }
      final date = req.url.pathSegments.last;
      if (req.method == 'DELETE') {
        entries.remove(date);
        return http.Response('', 204);
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json(entries[date] = {...body, 'date': date});
    }
    return http.Response('{"error":"not found"}', 404);
  });

  static http.Response _json(Object body) => http.Response(jsonEncode(body),
      200, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  late _FakeDeviceKey deviceKey;
  late ApiClient api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {'session_token': 'expired', 'device_key_id': 'k1'});
    server = _Server();
    deviceKey = _FakeDeviceKey();
    api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://api.example',
        workosClientId: 'client',
        redirectUri: 'com.jobucaldas.a217://auth/callback',
      ),
      httpClient: server.client,
      localStore: MemoryLocalStore(),
      deviceKey: deviceKey,
    );
  });

  test('an expired session is renewed with the device key', () async {
    final session = await api.currentSession();
    expect(session.user?.id, 'u1');
    expect(deviceKey.signed, ['217 device session v1\nk1\nc1']);
    expect(await api.readSessionToken(), 'fresh');
  });

  test('offline: opens signed in from the device and queues edits', () async {
    server.entries['2026-10-01'] = {'date': '2026-10-01', 'taken': true};
    await api.currentSession();
    expect(await api.listEntries(2026, 10), hasLength(1));

    server.up = false;
    final session = await api.currentSession();
    expect(session.user?.id, 'u1', reason: 'cached session while offline');
    await api.upsertEntry('2026-10-02', taken: false, notes: 'offline');
    await api.deleteEntry('2026-10-01');
    expect(api.offline.value, isTrue);
    expect(api.pendingWrites.value, 2);
    final month = await api.listEntries(2026, 10);
    expect(month.map((e) => e.date), ['2026-10-02']);

    server.up = true;
    await api.syncPending();
    expect(api.pendingWrites.value, 0);
    expect(server.entries.keys, ['2026-10-02']);
    expect(server.entries['2026-10-02']!['notes'], 'offline');
  });

  test('an edit the server refuses is dropped and reported', () async {
    await api.currentSession();
    server.refuseWritesWith = 400;
    await expectLater(
      api.upsertEntry('2026-10-03', taken: true),
      throwsA(isA<ApiException>()),
    );
    expect(api.pendingWrites.value, 0);
  });

  test('a revoked device key signs the device out', () async {
    server.deviceRevoked = true;
    final session = await api.currentSession();
    expect(session.user, isNull);
    expect(deviceKey.deleted, isTrue);
    expect(await api.readSessionToken(), isNull);
  });
}
