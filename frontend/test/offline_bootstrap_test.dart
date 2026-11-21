import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/offline/local_store.dart';
import 'package:a217/src/offline/local_store_memory.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/calendar_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() =>
      FlutterSecureStorage.setMockInitialValues({'session_token': 'kept'}));

  testWidgets(
      'first calendar frame shows cached status, note and prediction with '
      'stable bounds, and late cycle updates after unchanged revalidation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u1');
    await local.writeDoc(
      'u1',
      'session',
      jsonEncode({
        'user': {
          'id': 'u1',
          'email': 'owner@example.com',
          'name': 'Owner',
          'role': 'owner',
        },
      }),
    );
    await local.replaceMonth('u1', 2026, 11, const [
      Entry(date: '2026-11-05', taken: true, notes: '', period: true),
      Entry(date: '2026-11-21', taken: true, notes: 'morning pill'),
    ]);
    await local.replaceMonth('u1', 2026, 10, const []);
    await local.replaceMonth('u1', 2026, 12, const []);
    await local.writeDoc(
      'u1',
      'cycle',
      jsonEncode({
        'cycle_length': 28,
        'period_length': 5,
        'period_starts': ['2026-10-30'],
        'predictions': [
          {
            'period_start': '2026-11-27',
            'period_end': '2026-12-01',
            'pms_start': '2026-11-20',
            'pms_end': '2026-11-27',
          },
        ],
      }),
    );

    final sessionGate = Completer<void>();
    final entriesGate = Completer<void>();
    final cycleGate = Completer<void>();

    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://test.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/config':
            return http.Response(jsonEncode({'authkit': true}), 200);
          case '/api/auth/session':
            await sessionGate.future;
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u1',
                  'email': 'owner@example.com',
                  'name': 'Owner',
                  'role': 'owner',
                },
                'consent': {'version': 1, 'required': false},
              }),
              200,
            );
          case '/api/entries':
            await entriesGate.future;
            final month = request.url.queryParameters['month'];
            final year = request.url.queryParameters['year'];
            if (year == '2026' && month == '11') {
              return http.Response(
                jsonEncode({
                  'entries': [
                    {
                      'date': '2026-11-05',
                      'taken': true,
                      'notes': '',
                      'heart': false,
                      'period': true,
                    },
                    {
                      'date': '2026-11-21',
                      'taken': false,
                      'notes': 'morning pill',
                      'heart': false,
                      'period': false,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'entries': []}), 200);
          case '/api/cycle':
            await cycleGate.future;
            return http.Response(
              jsonEncode({
                'cycle_length': 28,
                'period_length': 5,
                'period_starts': ['2026-10-30'],
                'predictions': [
                  {
                    'period_start': '2026-11-29',
                    'period_end': '2026-12-03',
                    'pms_start': '2026-11-22',
                    'pms_end': '2026-11-29',
                  },
                ],
              }),
              200,
            );
          default:
            return http.Response('{}', 200);
        }
      }),
      localStore: local,
    );

    await tester.pumpWidget(
      App217(config: api.config, api: api, clock: () => fixedNow),
    );
    // Advance only enough for the local reads to land while every network
    // request stays gated.
    await tester.pump();
    await tester.pump();

    // Very first calendar frame is already populated from local cache.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('morning pill'), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-line')), findsOneWidget);
    expect(find.textContaining('Nov 27'), findsOneWidget);

    final initialGridRect = tester.getRect(find.byKey(const ValueKey('2026-11')));

    // Entries answer first so CalendarScreen launches getCycle(), then the
    // unchanged background session revalidation lands BEFORE getCycle()
    // returns. Revalidation must not drop the in-flight cycle update.
    entriesGate.complete();
    await tester.pump();
    await tester.pump();

    sessionGate.complete();
    await tester.pump();
    await tester.pump();

    // Now release the late cycle response with zero user input.
    cycleGate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Taken'), findsNothing);
    expect(find.textContaining('Nov 29'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('2026-11'))),
      initialGridRect,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a failing local read still opens the app without leaking auth',
      (tester) async {
    FlutterSecureStoragePlatform.instance = _ThrowingOnRead();
    final requests = <http.Request>[];
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://default.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
      localStore: _ThrowingLocalStore(),
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
    expect(requests, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
      'a failing api_base_url read with a valid token never sends credentials '
      'to the default server', (tester) async {
    FlutterSecureStoragePlatform.instance = _ThrowOnApiBaseOnly({
      'session_token': 'custom-server-secret-token',
    });
    final requests = <http.Request>[];
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://default.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
      localStore: MemoryLocalStore(),
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(requests, isEmpty);
    expect(api.apiBaseResolved, isFalse);
    await expectLater(api.currentSession(), throwsStateError);
    expect(requests, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test(
      'stale startup probe returning user:null after server switch does not '
      'clear new credentials or overwrite new server config', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final oldConfigGate = Completer<void>();
    final oldSessionGate = Completer<void>();
    final local = MemoryLocalStore();
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://old.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.host == 'old.example' &&
            request.url.path == '/api/auth/config') {
          await oldConfigGate.future;
          return http.Response(
            jsonEncode({'authkit': true, 'workos_user_deletion': true}),
            200,
          );
        }
        if (request.url.host == 'old.example' &&
            request.url.path == '/api/auth/session') {
          await oldSessionGate.future;
          return http.Response(jsonEncode({'user': null}), 200);
        }
        if (request.url.host == 'new.example' &&
            request.url.path == '/api/auth/config') {
          return http.Response(
            jsonEncode({'authkit': true, 'workos_user_deletion': false}),
            200,
          );
        }
        if (request.url.host == 'new.example' &&
            request.url.path == '/api/auth/session') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'u-new',
                'email': 'new@example.com',
                'role': 'owner',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
      localStore: local,
    );

    // Start the old server's startup probes.
    final oldConfig = api.loadAuthConfig();
    final oldSession = api.currentSession();

    // Before they finish, switch to a new server and establish a new session.
    expect(await api.setApiBaseUrl('https://new.example'), isTrue);
    await api.loadAuthConfig();
    await api.saveSessionToken('fresh-token');
    final newSession = await api.currentSession();
    expect(newSession.user?.id, 'u-new');
    expect(api.workosUserDeletion, isFalse);

    // Release the stale probes from old.example.
    oldConfigGate.complete();
    oldSessionGate.complete();
    await oldConfig;
    await expectLater(oldSession, throwsA(isA<StaleAuthScopeException>()));

    // New server's config, token, and cached session survive untouched.
    expect(api.workosUserDeletion, isFalse);
    expect(await api.readSessionToken(), 'fresh-token');
    expect((await api.cachedSession())?.user?.id, 'u-new');
  });
}

/// Throws only when reading `api_base_url`; other keys (like `session_token`)
/// still read cleanly to test partial storage failure.
class _ThrowOnApiBaseOnly extends FlutterSecureStoragePlatform {
  _ThrowOnApiBaseOnly(Map<String, String> values) : _values = Map.of(values);

  final Map<String, String> _values;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (key == 'api_base_url') throw StateError('api_base_url read failed');
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(_values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

/// Every storage read throws, as a broken platform keystore would.
class _ThrowingOnRead extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      throw StateError('storage broken');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      throw StateError('storage broken');

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

/// Every local-store read throws, as a corrupt database would.
class _ThrowingLocalStore implements LocalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('store broken');
}
