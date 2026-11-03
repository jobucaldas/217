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
import 'package:a217/src/offline/local_store_memory.dart';
import 'package:a217/src/screens/calendar_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('cold start opens the offline copy without waiting for the server',
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
}
