import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/sign_in_methods_section.dart';

const strings = Strings(AppLanguage.en);

ApiClient client() => ApiClient(
      AppConfig(
        apiBaseUrl: 'https://example.test',
        workosClientId: '',
        redirectUri: 'com.caldasstudios.app217://auth/callback',
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/config') {
          return http.Response(jsonEncode({
            'authkit': false,
            'workos': false,
            'password': false,
            'oidc': {'name': 'Example'},
          }), 200);
        }
        if (request.url.path == '/api/account/oidc') {
          return http.Response('{"error":"set up another sign-in method first"}', 409);
        }
        return http.Response('{}', 404);
      }),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('OIDC-only sign-in has no password form', (tester) async {
    final api = client();
    await api.loadAuthConfig();
    await tester.pumpWidget(MaterialApp(home: AuthScreen(
      strings: strings, api: api, onSignedIn: (_) async {},
      onSignInOIDC: () async {},
    )));
    expect(find.text('Continue with Example'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    expect(find.byKey(const ValueKey('auth-sign-in')), findsNothing);
  });

  test('an OIDC-only server passes the server check', () async {
    expect(await client().checkServer(), ServerCheck.ok);
  });

  for (final linked in [false, true]) {
    testWidgets('OIDC settings reflect connected=$linked', (tester) async {
      final api = client();
      await api.loadAuthConfig();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SignInMethodsSection(
        api: api, strings: strings,
        user: User(id: 'u1', email: 'user@example.test', name: '', oidcLinked: linked),
        group: (children) => Column(children: children),
      ))));
      expect(find.text(linked ? 'Connected' : 'Not connected'), findsOneWidget);
      expect(find.text(linked ? 'Disconnect' : 'Connect'), findsOneWidget);
      if (linked) {
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
        expect(find.text('Set up another sign-in method first.'), findsOneWidget);
      }
    });
  }
}
