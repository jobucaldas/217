import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/offline/local_store.dart';
import 'package:a217/src/offline/local_store_memory.dart';
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
}
