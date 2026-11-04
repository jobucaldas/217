import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/offline/local_store.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/offline/local_store_memory.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/calendar_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets(
      'cold start opens the offline copy without waiting for the server',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'kept'});
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
    // A server that never answers: every request ends at the client timeout.
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((_) => Completer<http.Response>().future),
      localStore: local,
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    // Well under the 20 s request timeout.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);

    // The timeout elapses: the offline copy stays, nobody is signed out.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump(const Duration(seconds: 25));
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(api.offline.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  Future<MemoryLocalStore> cachedOwner() async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'kept'});
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
    return local;
  }

  // Server answering /api/auth/session with [session]; anything else is {}.
  ApiClient serverAnswering(MemoryLocalStore local, http.Response session) =>
      ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async =>
            request.url.path == '/api/auth/session'
                ? session
                : http.Response('{}', 200)),
        localStore: local,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets(
      'signed out by the server: sign-in screen, notifications and '
      'local copy cleared', (tester) async {
    final local = await cachedOwner();
    final api = serverAnswering(local, http.Response('{"user":null}', 200));
    var dailyCancels = 0;
    var partnerCancels = 0;

    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: ({
        required enabled,
        required timeHhMm,
        required title,
        required body,
        repeatEnabled = false,
        repeatMinutes = 15,
        todayLogged = false,
      }) async {
        if (!enabled) dailyCancels++;
        return const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled);
      },
      partnerAlertCanceller: () async => partnerCancels++,
    ));
    await settle(tester);

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(CalendarScreen), findsNothing);
    expect(dailyCancels, greaterThan(0));
    expect(partnerCancels, greaterThan(0));
    expect(await local.readDoc('u1', 'session'), isNull);
    expect(await local.readDoc(localGlobalUser, 'last_user'), isNull);
  });

  testWidgets('another account on the server: the old local copy is dropped',
      (tester) async {
    final local = await cachedOwner();
    final api = serverAnswering(
      local,
      http.Response(
        jsonEncode({
          'user': {
            'id': 'u2',
            'email': 'other@example.com',
            'name': 'Other',
            'role': 'owner',
          },
        }),
        200,
      ),
    );

    await tester.pumpWidget(App217(config: api.config, api: api));
    await settle(tester);

    expect(await local.readDoc('u1', 'session'), isNull);
    expect(await local.readDoc(localGlobalUser, 'last_user'), 'u2');
  });

  testWidgets('server error: the offline copy stays', (tester) async {
    final local = await cachedOwner();
    final api = serverAnswering(local, http.Response('boom', 500));

    await tester.pumpWidget(App217(config: api.config, api: api));
    await settle(tester);

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    expect(await local.readDoc('u1', 'session'), isNotNull);
  });
}
