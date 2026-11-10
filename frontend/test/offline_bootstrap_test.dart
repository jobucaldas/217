import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/offline/local_store.dart';
import 'package:a217/src/offline/local_store_memory.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/calendar_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'kept'}));

  testWidgets('cached month and predictions show before the server answers',
      (tester) async {
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
    await local.writeDoc(
      'u1',
      'cycle',
      jsonEncode({
        'cycle_length': 28,
        'period_length': 5,
        'period_starts': ['2026-01-05'],
        'predictions': [
          {
            'period_start': '2026-02-01',
            'period_end': '2026-02-05',
            'pms_start': '2026-01-29',
            'pms_end': '2026-02-01',
          },
        ],
      }),
    );
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((_) => Completer<http.Response>().future),
      localStore: local,
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    // Two pumps of the first frames: enough for the local reads to land,
    // far under any request timeout.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CalendarScreen), findsOneWidget);
    // The calendar draws the cached month instead of a spinner.
    expect(find.text('Loading…'), findsNothing);

    // Drop the tree and flush the background session request's timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a failing local read still opens the app', (tester) async {
    // Every storage read throws (a broken keystore, a corrupt database):
    // the bootstrap must fall back to its defaults instead of stalling on
    // the splash, and still reach the signed-out shell.
    FlutterSecureStoragePlatform.instance = _ThrowingOnRead();
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((_) => Completer<http.Response>().future),
      localStore: _ThrowingLocalStore(),
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // The app rendered (signed-out shell, no cached session) despite the
    // failing reads; the splash did not stick.
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
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
