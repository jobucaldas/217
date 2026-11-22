import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/auth/device_key.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/offline/local_store.dart';
import 'package:a217/src/offline/local_store_memory.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/day_summary.dart';
import 'package:a217/src/screens/share_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() =>
      FlutterSecureStorage.setMockInitialValues({'session_token': 'kept'}));

  testWidgets(
      'first calendar frame shows cached status, note and prediction with '
      'stable bounds, and late cycle updates after owner open->active share '
      'revalidation', (tester) async {
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
        'share': {'status': 'open', 'code': 'INV123'},
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
                // Owner's invite transitioned open -> active; calendar access
                // is unchanged so in-flight cycle work must not be dropped.
                'share': {
                  'status': 'active',
                  'partner_email': 'partner@example.com',
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
    // owner session revalidation (open -> active) lands BEFORE getCycle()
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
      'a failing api_base_url read blocks auth and explicitly saving the '
      'default clears custom-server credentials first', (tester) async {
    final storage = _ThrowOnApiBaseOnly({
      'session_token': 'custom-server-secret-token',
      'device_key_id': 'custom-device-key',
    });
    FlutterSecureStoragePlatform.instance = storage;
    final deviceKey = _RecordingDeviceKey();
    final requests = <http.Request>[];
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://default.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'user': null}), 200);
      }),
      localStore: MemoryLocalStore(),
      deviceKey: deviceKey,
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(requests, isEmpty);
    expect(api.apiBaseResolved, isFalse);
    await expectLater(api.currentSession(), throwsStateError);
    expect(requests, isEmpty);

    // Explicitly saving the default server must still treat the unresolved
    // base as a server change and wipe the custom server's token & device key
    // before allowing authenticated requests.
    expect(await api.setApiBaseUrl(''), isTrue);
    expect(api.apiBaseResolved, isTrue);
    expect(await api.readSessionToken(), isNull);
    expect(deviceKey.deletedCount, 1);

    await api.currentSession();
    expect(requests, hasLength(1));
    expect(requests.single.headers['Authorization'], isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test(
      'switching servers clears old credentials and blocks auth before '
      'publishing the new server URL', () async {
    final ops = <String>[];
    late ApiClient api;
    final storage = _RecordingStorage(
      {
        'api_base_url': 'https://old.example',
        'session_token': 'old-secret',
        'device_key_id': 'old-dev-key',
      },
      onOp: (op, key, value) {
        ops.add('$op:$key@${api.config.apiBaseUrl}:resolved=${api.apiBaseResolved}');
      },
    );
    FlutterSecureStoragePlatform.instance = storage;
    final deviceKey = _RecordingDeviceKey();
    api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://old.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      localStore: MemoryLocalStore(),
      deviceKey: deviceKey,
    );

    expect(await api.setApiBaseUrl('https://new.example'), isTrue);
    expect(api.config.apiBaseUrl, 'https://new.example');
    expect(api.apiBaseResolved, isTrue);
    expect(deviceKey.deletedCount, 1);

    final deleteTokenIdx =
        ops.indexWhere((e) => e.startsWith('delete:session_token@'));
    final deleteKeyIdx =
        ops.indexWhere((e) => e.startsWith('delete:device_key_id@'));
    final writeBaseIdx =
        ops.indexWhere((e) => e.startsWith('write:api_base_url@'));
    expect(deleteTokenIdx, greaterThanOrEqualTo(0));
    expect(deleteKeyIdx, greaterThan(deleteTokenIdx));
    expect(writeBaseIdx, greaterThan(deleteKeyIdx));
    // Throughout cleanup and before publishing, old URL remained in config and
    // authenticated requests were blocked (resolved=false).
    expect(ops[deleteTokenIdx], contains('@https://old.example:resolved=false'));
    expect(ops[deleteKeyIdx], contains('@https://old.example:resolved=false'));
    expect(ops[writeBaseIdx], contains('@https://old.example:resolved=false'));
  });

  testWidgets(
      'partner whose share is revoked and who rejoins a different owner never '
      'sees the former owner cached calendar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-partner');
    await local.writeDoc(
      'u-partner',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-partner',
          'email': 'partner@example.com',
          'name': 'Partner',
          'role': 'partner',
        },
        'share': {
          'status': 'active',
          'owner_email': 'owner-a@example.com',
          'can_edit_calendar': false,
        },
      }),
    );
    await local.writeDoc(
      'u-partner',
      'calendar',
      'partner:active:owner-a@example.com',
    );
    await local.replaceMonth('u-partner', 2026, 11, const [
      Entry(date: '2026-11-21', taken: true, notes: 'owner-a private note'),
    ]);
    await local.replaceMonth('u-partner', 2026, 10, const []);
    await local.replaceMonth('u-partner', 2026, 12, const []);
    await local.writeDoc(
      'u-partner',
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

    var joinedOwnerB = false;
    final ownerBEntriesGate = Completer<void>();
    final ownerBCycleGate = Completer<void>();

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
            if (!joinedOwnerB) {
              return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'u-partner',
                    'email': 'partner@example.com',
                    'name': 'Partner',
                    'role': 'partner',
                  },
                  'share': {'status': 'revoked', 'can_edit_calendar': false},
                  'consent': {'version': 1, 'required': false},
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u-partner',
                  'email': 'partner@example.com',
                  'name': 'Partner',
                  'role': 'partner',
                },
                'share': {
                  'status': 'active',
                  'owner_email': 'owner-b@example.com',
                  'can_edit_calendar': false,
                },
                'consent': {'version': 1, 'required': false},
              }),
              200,
            );
          case '/api/share/accept':
            joinedOwnerB = true;
            return http.Response(
              jsonEncode({
                'status': 'active',
                'owner_email': 'owner-b@example.com',
                'can_edit_calendar': false,
              }),
              200,
            );
          case '/api/entries':
            if (joinedOwnerB) await ownerBEntriesGate.future;
            return http.Response(jsonEncode({'entries': []}), 200);
          case '/api/cycle':
            if (joinedOwnerB) await ownerBCycleGate.future;
            return http.Response(
              jsonEncode({
                'cycle_length': 0,
                'period_length': 0,
                'period_starts': [],
                'predictions': [],
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
    await tester.pumpAndSettle();

    // Startup revalidation revoked Owner A's share -> PartnerJoinScreen shown.
    expect(find.byType(PartnerJoinScreen), findsOneWidget);
    expect(find.byType(CalendarScreen), findsNothing);

    // Join Owner B while Owner B's calendar network responses stay held back.
    await tester.enterText(
      find.byKey(const ValueKey('partner-join-code')),
      'OWNERB',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Newly mounted calendar must NEVER show Owner A's private data.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('owner-a private note'), findsNothing);
    expect(find.text('Taken'), findsNothing);
    expect(find.textContaining('Nov 27'), findsNothing);

    ownerBEntriesGate.complete();
    ownerBCycleGate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test(
      'stale startup probe returning user:null after server switch does not '
      'clear new credentials or overwrite new server config', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final oldConfigReached = Completer<void>();
    final oldSessionReached = Completer<void>();
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
          if (!oldConfigReached.isCompleted) oldConfigReached.complete();
          await oldConfigGate.future;
          return http.Response(
            jsonEncode({'authkit': true, 'workos_user_deletion': true}),
            200,
          );
        }
        if (request.url.host == 'old.example' &&
            request.url.path == '/api/auth/session') {
          if (!oldSessionReached.isCompleted) oldSessionReached.complete();
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

    // Start the old server's startup probes and wait until both are in flight.
    final oldConfig = api.loadAuthConfig();
    final oldSession = api.currentSession();
    final oldSessionExpect =
        expectLater(oldSession, throwsA(isA<StaleAuthScopeException>()));
    await Future.wait([oldConfigReached.future, oldSessionReached.future]);

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
    await oldSessionExpect;

    // New server's config, token, and cached session survive untouched.
    expect(api.workosUserDeletion, isFalse);
    expect(await api.readSessionToken(), 'fresh-token');
    expect((await api.cachedSession())?.user?.id, 'u-new');
  });

  test(
      'stale probe paused inside cached-session storage read cannot revert '
      'client account identity after a newer sign-in', () async {
    final pauseCachedTokenRead = Completer<void>();
    final cachedTokenReadReached = Completer<void>();
    var pausedOnce = false;
    final storage = _GatedTokenReadStorage(
      {'session_token': 'old-token'},
      shouldPauseRead: (key, count) {
        // First read is _sendOnce attaching Bearer token; second read is
        // _readCachedSession() after the 503 response.
        if (key == 'session_token' && count == 2 && !pausedOnce) {
          pausedOnce = true;
          cachedTokenReadReached.complete();
          return pauseCachedTokenRead.future;
        }
        return null;
      },
    );
    FlutterSecureStoragePlatform.instance = storage;

    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-old');
    await local.writeDoc(
      'u-old',
      'session',
      jsonEncode({
        'user': {'id': 'u-old', 'email': 'old@example.com', 'role': 'owner'},
      }),
    );
    await local.writeDoc(
      'u-old',
      'cycle',
      jsonEncode({
        'cycle_length': 28,
        'period_length': 5,
        'period_starts': ['2026-10-01'],
        'predictions': [],
      }),
    );

    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://old.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.host == 'old.example' &&
            request.url.path == '/api/auth/session') {
          return http.Response('unavailable', 503);
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
        return http.Response('{}', 200);
      }),
      localStore: local,
    );

    // Start old probe; it gets 503 and pauses inside _readCachedSession().
    final oldProbe = api.currentSession();
    await cachedTokenReadReached.future;

    // While paused inside storage, switch servers and establish Account B.
    expect(await api.setApiBaseUrl('https://new.example'), isTrue);
    await api.saveSessionToken('new-token');
    final newSession = await api.currentSession();
    expect(newSession.user?.id, 'u-new');
    await local.writeDoc(
      'u-new',
      'cycle',
      jsonEncode({
        'cycle_length': 30,
        'period_length': 4,
        'period_starts': ['2026-11-01'],
        'predictions': [],
      }),
    );

    // Release the paused storage read for the old probe.
    pauseCachedTokenRead.complete();
    await expectLater(oldProbe, throwsA(isA<StaleAuthScopeException>()));

    // Client's active account identity must still be u-new, not u-old.
    expect(await api.readSessionToken(), 'new-token');
    final cycle = await api.cachedCycle();
    expect(cycle?.cycleLength, 30);
  });

  test(
      'anonymous session arriving before same-server auth config does not '
      'discard authkit: true', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final configGate = Completer<void>();
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://test.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/config') {
          await configGate.future;
          return http.Response(
            jsonEncode({
              'authkit': true,
              'workos_user_deletion': true,
              'privacy_contact': 'privacy@example.com',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/session') {
          return http.Response(jsonEncode({'user': null}), 200);
        }
        return http.Response('{}', 404);
      }),
      localStore: MemoryLocalStore(),
    );

    // Start both concurrently, just like _loadConfigAndSession() on web.
    final configFuture = api.loadAuthConfig();
    final session = await api.currentSession();
    expect(session.user, isNull);

    // Now the same-server config finishes after clearSession() ran.
    configGate.complete();
    await configFuture;

    expect(api.authkit, isTrue);
    expect(api.workosUserDeletion, isTrue);
    expect(api.privacyContact, 'privacy@example.com');
  });

  test(
      'loadPersistedApiBase started during setApiBaseUrl cleanup cannot '
      'restore the old server URL in memory', () async {
    final cleanupReached = Completer<void>();
    final cleanupGate = Completer<void>();
    final storage = _GatedStorage(
      {
        'api_base_url': 'https://old.example',
        'session_token': 'old-token',
      },
      onDelete: (key) {
        if (key == 'session_token' && !cleanupReached.isCompleted) {
          cleanupReached.complete();
          return cleanupGate.future;
        }
        return null;
      },
    );
    FlutterSecureStoragePlatform.instance = storage;

    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://old.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      localStore: MemoryLocalStore(),
    );

    final switchFuture = api.setApiBaseUrl('https://new.example');
    await cleanupReached.future;
    expect(api.apiBaseResolved, isFalse);

    // Sign-in retry path sees apiBaseResolved == false during cleanup and calls
    // loadPersistedApiBase() concurrently.
    final reloadFuture = api.loadPersistedApiBase();

    cleanupGate.complete();
    expect(await switchFuture, isTrue);
    expect(await reloadFuture, isTrue);

    expect(api.config.apiBaseUrl, 'https://new.example');
    expect(api.apiBaseResolved, isTrue);
    expect(storage.values['api_base_url'], 'https://new.example');
  });

  testWidgets(
      'partner relinked active-to-active to another owner disposes the former '
      'owner calendar immediately on revalidation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-partner');
    await local.writeDoc(
      'u-partner',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-partner',
          'email': 'partner@example.com',
          'name': 'Partner',
          'role': 'partner',
        },
        'share': {
          'status': 'active',
          'owner_email': 'owner-a@example.com',
          'can_edit_calendar': false,
        },
      }),
    );
    await local.writeDoc(
      'u-partner',
      'calendar',
      'partner:active:owner-a@example.com',
    );
    await local.replaceMonth('u-partner', 2026, 11, const [
      Entry(date: '2026-11-21', taken: true, notes: 'owner-a private note'),
    ]);
    await local.replaceMonth('u-partner', 2026, 10, const []);
    await local.replaceMonth('u-partner', 2026, 12, const []);
    await local.writeDoc(
      'u-partner',
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
    final ownerBEntriesGate = Completer<void>();
    final ownerBCycleGate = Completer<void>();
    var revalidated = false;

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
            revalidated = true;
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u-partner',
                  'email': 'partner@example.com',
                  'name': 'Partner',
                  'role': 'partner',
                },
                // Relinked directly to Owner B on another device without ever
                // observing a revoked state on this device.
                'share': {
                  'status': 'active',
                  'owner_email': 'owner-b@example.com',
                  'can_edit_calendar': false,
                },
                'consent': {'version': 1, 'required': false},
              }),
              200,
            );
          case '/api/entries':
            await ownerBEntriesGate.future;
            if (revalidated &&
                request.url.queryParameters['year'] == '2026' &&
                request.url.queryParameters['month'] == '11') {
              return http.Response(
                jsonEncode({
                  'entries': [
                    {
                      'date': '2026-11-21',
                      'taken': false,
                      'notes': 'owner-b note',
                      'period': false,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'entries': []}), 200);
          case '/api/cycle':
            await ownerBCycleGate.future;
            return http.Response(
              jsonEncode({
                'cycle_length': 0,
                'period_length': 0,
                'period_starts': [],
                'predictions': [],
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
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Cached Owner A calendar appears before network reply.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('owner-a private note'), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);

    // Open Owner A's read-only day sheet while revalidation is still pending.
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExpandableDaySheet), findsOneWidget);

    // Revalidation reveals active share for Owner B while Owner B's network
    // calendar data is still pending.
    sessionGate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Owner A's private calendar AND open day sheet must already be dismissed.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(ExpandableDaySheet), findsNothing);
    expect(find.text('owner-a private note'), findsNothing);
    expect(find.text('Taken'), findsNothing);
    expect(find.textContaining('Nov 27'), findsNothing);

    // Once Owner B's data arrives, Owner B's entry renders cleanly.
    ownerBEntriesGate.complete();
    ownerBCycleGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ExpandableDaySheet), findsNothing);
    expect(find.text('owner-b note'), findsOneWidget);
    expect(find.text('owner-a private note'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
      'release build with empty defaultApiBaseUrl and saved custom server '
      'opens straight to cached calendar offline-first', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    FlutterSecureStorage.setMockInitialValues({
      'api_base_url': 'https://custom.example',
      'session_token': 'custom-tok',
    });

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-custom');
    await local.writeDoc(
      'u-custom',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-custom',
          'email': 'owner@custom.example',
          'name': 'Custom Owner',
          'role': 'owner',
        },
        'share': {'status': 'none'},
      }),
    );
    await local.replaceMonth('u-custom', 2026, 11, const [
      Entry(date: '2026-11-21', taken: true, notes: 'custom server note'),
    ]);
    await local.replaceMonth('u-custom', 2026, 10, const []);
    await local.replaceMonth('u-custom', 2026, 12, const []);
    await local.writeDoc(
      'u-custom',
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

    final networkGate = Completer<void>();
    final hosts = <String>[];
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: '',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        hosts.add(request.url.host);
        await networkGate.future;
        return http.Response('unavailable', 503);
      }),
      localStore: local,
    );

    await tester.pumpWidget(
      App217(config: api.config, api: api, clock: () => fixedNow),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Populated cached calendar appears immediately before any network reply.
    expect(api.config.apiBaseUrl, 'https://custom.example');
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('custom server note'), findsOneWidget);
    expect(find.textContaining('Nov 27'), findsOneWidget);
    expect(hosts, isNotEmpty);
    expect(hosts.every((h) => h == 'custom.example'), isTrue);

    networkGate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test(
      'concurrent currentSession started during signInWithWorkOS commit cannot '
      'read empty credentials and wipe the new session', () async {
    const channel = MethodChannel('flutter_web_auth_2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') {
        final args = call.arguments as Map<Object?, Object?>;
        final authUri = Uri.parse(args['url'] as String);
        final state = authUri.queryParameters['state'];
        return '$androidRedirectUri?code=auth-code-1&state=$state';
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final tokenWriteReached = Completer<void>();
    final tokenWriteGate = Completer<void>();
    final storage = _GatedStorage(
      {},
      onWrite: (key, value) {
        if (key == 'session_token' && !tokenWriteReached.isCompleted) {
          tokenWriteReached.complete();
          return tokenWriteGate.future;
        }
        return null;
      },
    );
    FlutterSecureStoragePlatform.instance = storage;

    final local = MemoryLocalStore();
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://test.example',
        workosClientId: 'client_123',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/config') {
          return http.Response(
            jsonEncode({'authkit': true, 'workos_client_id': 'client_123'}),
            200,
          );
        }
        if (request.url.path == '/api/auth/workos/exchange') {
          return http.Response(
            jsonEncode({
              'session_token': 'new-sign-in-token',
              'user': {
                'id': 'u-signed-in',
                'email': 'signedin@example.com',
                'role': 'owner',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/session') {
          if (request.headers['Authorization'] != 'Bearer new-sign-in-token') {
            return http.Response(jsonEncode({'user': null}), 200);
          }
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'u-signed-in',
                'email': 'signedin@example.com',
                'role': 'owner',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
      localStore: local,
      deviceKey: _RecordingDeviceKey(),
    );

    final signInFuture = api.signInWithWorkOS();
    await tokenWriteReached.future;

    // A probe starting mid-commit must not capture the post-commit scope and
    // later wipe the newly saved token.
    final concurrentProbe = api.currentSession();
    final probeExpect =
        expectLater(concurrentProbe, throwsA(isA<StaleAuthScopeException>()));

    tokenWriteGate.complete();
    final user = await signInFuture;
    expect(user.id, 'u-signed-in');
    await probeExpect;

    expect(await api.readSessionToken(), 'new-sign-in-token');
    expect((await api.cachedSession())?.user?.id, 'u-signed-in');
  });

  test(
      'stale session and share mutation responses arriving after a server '
      'switch throw StaleAuthScopeException and preserve the new account',
      () async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'old-tok'});
    final gate = Completer<void>();
    var reachedCount = 0;
    final allReached = Completer<void>();

    final local = MemoryLocalStore();
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://old.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.host == 'old.example') {
          reachedCount++;
          if (reachedCount == 4 && !allReached.isCompleted) {
            allReached.complete();
          }
          await gate.future;
          if (request.url.path == '/api/share/accept') {
            return http.Response(
              jsonEncode({
                'status': 'active',
                'owner_email': 'old-owner@example.com',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'u-old',
                'email': 'old@example.com',
                'role': 'owner',
              },
            }),
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

    final fProfile = api.updateProfile(displayName: 'Old');
    final fRole = api.setRole('owner');
    final fConsent = api.acceptConsent(1);
    final fAccept = api.acceptShare('OLDCODE');
    final expects = [
      expectLater(fProfile, throwsA(isA<StaleAuthScopeException>())),
      expectLater(fRole, throwsA(isA<StaleAuthScopeException>())),
      expectLater(fConsent, throwsA(isA<StaleAuthScopeException>())),
      expectLater(fAccept, throwsA(isA<StaleAuthScopeException>())),
    ];
    await allReached.future;

    // Switch servers and sign in as a new account before the old calls reply.
    expect(await api.setApiBaseUrl('https://new.example'), isTrue);
    await api.saveSessionToken('new-tok');
    expect((await api.currentSession()).user?.id, 'u-new');

    gate.complete();
    await Future.wait(expects);

    expect(await api.readSessionToken(), 'new-tok');
    expect((await api.cachedSession())?.user?.id, 'u-new');
  });

  testWidgets(
      'open note dialog dismisses immediately on active-to-active partner '
      'relink', (tester) async {
    tester.view.devicePixelRatio = 1;
    // Short viewport so the note renders as a tag opening showDayNoteCard.
    tester.view.physicalSize = const Size(412, 620);
    addTearDown(tester.view.reset);

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-partner');
    await local.writeDoc(
      'u-partner',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-partner',
          'email': 'partner@example.com',
          'name': 'Partner',
          'role': 'partner',
        },
        'share': {
          'status': 'active',
          'owner_email': 'owner-a@example.com',
          'can_edit_calendar': false,
        },
      }),
    );
    await local.writeDoc(
      'u-partner',
      'calendar',
      'partner:active:owner-a@example.com',
    );
    await local.replaceMonth('u-partner', 2026, 11, const [
      Entry(date: '2026-11-21', taken: true, notes: 'owner-a secret note'),
    ]);
    await local.replaceMonth('u-partner', 2026, 10, const []);
    await local.replaceMonth('u-partner', 2026, 12, const []);

    final sessionGate = Completer<void>();
    final entriesGate = Completer<void>();
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
                  'id': 'u-partner',
                  'email': 'partner@example.com',
                  'name': 'Partner',
                  'role': 'partner',
                },
                'share': {
                  'status': 'active',
                  'owner_email': 'owner-b@example.com',
                  'can_edit_calendar': false,
                },
                'consent': {'version': 1, 'required': false},
              }),
              200,
            );
          case '/api/entries':
            await entriesGate.future;
            return http.Response(jsonEncode({'entries': []}), 200);
          case '/api/cycle':
            await entriesGate.future;
            return http.Response(
              jsonEncode({
                'cycle_length': 0,
                'period_length': 0,
                'period_starts': [],
                'predictions': [],
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
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('day-tag-note')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-tag-note')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('day-note-card')), findsOneWidget);
    expect(find.text('owner-a secret note'), findsOneWidget);

    sessionGate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('day-note-card')), findsNothing);
    expect(find.text('owner-a secret note'), findsNothing);

    entriesGate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
      'confirmed session relink dismisses open overlay immediately while '
      '/api/auth/config is stalled and even if config later returns 503',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final fixedNow = DateTime(2026, 11, 21, 10, 0);
    final local = MemoryLocalStore();
    await local.writeDoc(localGlobalUser, 'last_user', 'u-partner');
    await local.writeDoc(
      'u-partner',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-partner',
          'email': 'partner@example.com',
          'name': 'Partner',
          'role': 'partner',
        },
        'share': {
          'status': 'active',
          'owner_email': 'owner-a@example.com',
          'can_edit_calendar': false,
        },
      }),
    );
    await local.writeDoc(
      'u-partner',
      'calendar',
      'partner:active:owner-a@example.com',
    );
    await local.replaceMonth('u-partner', 2026, 11, const [
      Entry(date: '2026-11-21', taken: true, notes: 'owner-a private note'),
    ]);
    await local.replaceMonth('u-partner', 2026, 10, const []);
    await local.replaceMonth('u-partner', 2026, 12, const []);

    final sessionGate = Completer<void>();
    final configGate = Completer<void>();
    final entriesGate = Completer<void>();
    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://test.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/session':
            await sessionGate.future;
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u-partner',
                  'email': 'partner@example.com',
                  'name': 'Partner',
                  'role': 'partner',
                },
                'share': {
                  'status': 'active',
                  'owner_email': 'owner-b@example.com',
                  'can_edit_calendar': false,
                },
                'consent': {'version': 1, 'required': false},
              }),
              200,
            );
          case '/api/auth/config':
            await configGate.future;
            return http.Response('unavailable', 503);
          case '/api/entries':
            await entriesGate.future;
            return http.Response(jsonEncode({'entries': []}), 200);
          case '/api/cycle':
            await entriesGate.future;
            return http.Response(
              jsonEncode({
                'cycle_length': 0,
                'period_length': 0,
                'period_starts': [],
                'predictions': [],
              }),
              200,
            );
          default:
            await entriesGate.future;
            return http.Response('{}', 200);
        }
      }),
      localStore: local,
    );

    await tester.pumpWidget(
      App217(config: api.config, api: api, clock: () => fixedNow),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Open Owner A's read-only day sheet while both session and config stall.
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExpandableDaySheet), findsOneWidget);
    expect(find.text('owner-a private note'), findsWidgets);

    // /api/auth/session confirms Owner B while /api/auth/config stays stalled.
    sessionGate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Owner A's open sheet and calendar MUST already be gone before config replies.
    expect(configGate.isCompleted, isFalse);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(ExpandableDaySheet), findsNothing);
    expect(find.text('owner-a private note'), findsNothing);
    expect(find.text('Taken'), findsNothing);

    // Even when /api/auth/config later returns 503 and sets offline=true,
    // Owner B's confirmed session remains active.
    configGate.complete();
    await tester.pump();
    await tester.pump();
    expect(api.offline.value, isTrue);
    expect(find.text('owner-a private note'), findsNothing);
    expect(find.text('Taken'), findsNothing);

    entriesGate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test(
      'late listEntries paused in pendingWrites cannot repopulate cleared '
      'cache after partner relink', () async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
    final pendingReached = Completer<void>();
    final pendingGate = Completer<void>();
    final entriesHttpGate = Completer<void>();
    final relinkHttpReached = Completer<void>();
    final relinkResponseGate = Completer<void>();
    var pauseNextPending = false;
    final local = _GatedPendingWritesStore(
      onPendingWrites: () {
        if (pauseNextPending && !pendingReached.isCompleted) {
          pauseNextPending = false;
          pendingReached.complete();
          return pendingGate.future;
        }
        return null;
      },
    );
    await local.writeDoc(localGlobalUser, 'last_user', 'u-partner');
    await local.writeDoc(
      'u-partner',
      'session',
      jsonEncode({
        'user': {
          'id': 'u-partner',
          'email': 'partner@example.com',
          'role': 'partner',
        },
        'share': {
          'status': 'active',
          'owner_email': 'owner-a@example.com',
          'can_edit_calendar': false,
        },
      }),
    );
    await local.writeDoc(
      'u-partner',
      'calendar',
      'partner:active:owner-a@example.com',
    );

    final api = ApiClient(
      AppConfig(
        apiBaseUrl: 'https://test.example',
        workosClientId: '',
        redirectUri: androidRedirectUri,
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/entries') {
          await entriesHttpGate.future;
          return http.Response(
            jsonEncode({
              'entries': [
                {
                  'date': '2026-11-21',
                  'taken': true,
                  'notes': 'owner-a private entry',
                  'period': false,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/session') {
          if (!relinkHttpReached.isCompleted) relinkHttpReached.complete();
          await relinkResponseGate.future;
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'u-partner',
                'email': 'partner@example.com',
                'role': 'partner',
              },
              'share': {
                'status': 'active',
                'owner_email': 'owner-b@example.com',
                'can_edit_calendar': false,
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
      localStore: local,
    );

    // Adopt cached session for Owner A so listEntries captures Owner A's scope.
    expect((await api.cachedSession())?.user?.id, 'u-partner');
    pauseNextPending = true;

    // Launch both requests so currentSession() has already sent its HTTP
    // request before listEntries() pauses inside pendingWrites().
    final entriesFuture = api.listEntries(2026, 11);
    final relinkFuture = api.currentSession();
    await relinkHttpReached.future;

    entriesHttpGate.complete();
    await pendingReached.future;

    // Deliver the relink response while listEntries() is still blocked inside
    // pendingWrites(), giving an unserialized implementation time to run
    // clearCalendar() before replaceMonth() executes.
    relinkResponseGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    pendingGate.complete();
    await Future.wait([entriesFuture, relinkFuture]);

    // Owner A's response must NOT survive in the local cache after relink.
    expect(await api.cachedMonth(2026, 11), isNull);
  });
}

class _GatedPendingWritesStore extends MemoryLocalStore {
  _GatedPendingWritesStore({required this.onPendingWrites});

  final Future<void>? Function() onPendingWrites;

  @override
  Future<List<PendingWrite>> pendingWrites(String userId) async {
    final gate = onPendingWrites();
    if (gate != null) await gate;
    return super.pendingWrites(userId);
  }
}

class _RecordingDeviceKey extends DeviceKey {
  int deletedCount = 0;

  @override
  Future<String?> create() async => null;

  @override
  Future<String?> sign(String message) async => null;

  @override
  Future<void> delete() async {
    deletedCount++;
  }
}

class _RecordingStorage extends FlutterSecureStoragePlatform {
  _RecordingStorage(
    Map<String, String> values, {
    required this.onOp,
  }) : _values = Map.of(values);

  final Map<String, String> _values;
  final void Function(String op, String key, String? value) onOp;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    onOp('read', key, _values[key]);
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    onOp('write', key, value);
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
    onOp('delete', key, null);
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

class _GatedTokenReadStorage extends FlutterSecureStoragePlatform {
  _GatedTokenReadStorage(
    Map<String, String> values, {
    required this.shouldPauseRead,
  }) : _values = Map.of(values);

  final Map<String, String> _values;
  final Future<void>? Function(String key, int readCount) shouldPauseRead;
  int _tokenReads = 0;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final value = _values[key];
    if (key == 'session_token') {
      _tokenReads++;
      final gate = shouldPauseRead(key, _tokenReads);
      if (gate != null) await gate;
    }
    return value;
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

class _GatedStorage extends FlutterSecureStoragePlatform {
  _GatedStorage(
    Map<String, String> initial, {
    this.onWrite,
    this.onDelete,
  }) : values = Map.of(initial);

  final Map<String, String> values;
  final Future<void>? Function(String key, String value)? onWrite;
  final Future<void>? Function(String key)? onDelete;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final gate = onWrite?.call(key, value);
    if (gate != null) await gate;
    values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final gate = onDelete?.call(key);
    if (gate != null) await gate;
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }
}
