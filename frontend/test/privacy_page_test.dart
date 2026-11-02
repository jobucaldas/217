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
import 'package:a217/src/screens/privacy_page.dart';
import 'package:a217/src/theme/app_theme.dart';

const _user =
    User(id: 'u1', email: 'me@example.com', name: 'Me', role: 'owner');

/// The browser's session on the server: [recent] is `recent_sign_in`.
class _Server {
  _Server({this.recent = true, this.reauthOnDelete = false});

  bool recent;

  /// The server wants a fresher sign-in than the session reported.
  bool reauthOnDelete;
  final calls = <String>[];

  ApiClient client() => ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          switch (request.url.path) {
            case '/api/auth/config':
              return http.Response(
                  jsonEncode({'authkit': true, 'workos_user_deletion': true}),
                  200);
            case '/api/auth/session':
              return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'u1',
                    'email': 'me@example.com',
                    'role': 'owner'
                  },
                  'consent': {'version': 1, 'required': false},
                  'recent_sign_in': recent,
                }),
                200,
              );
            case '/api/account':
              if (reauthOnDelete) {
                return http.Response('{"error":"reauth required"}', 403);
              }
              return http.Response('', 204);
            case '/api/account/export':
              return http.Response('{"user":{}}', 200, headers: {
                'content-disposition':
                    'attachment; filename="217-data-2026-11-02.json"',
              });
          }
          return http.Response('{}', 404);
        }),
      );
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(brightness: Brightness.light),
    home: page,
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('standalone pages are found by their web path', () {
    expect(webPageFor(Uri.parse('https://x.example/app/privacy?lang=pt')),
        WebPage.privacy);
    expect(webPageFor(Uri.parse('https://x.example/app/account/delete/')),
        WebPage.deleteAccount);
    expect(webPageFor(Uri.parse('https://x.example/app/')), isNull);
    expect(webPageFor(Uri.parse('https://x.example/api/privacy')), isNull);
  });

  testWidgets('signed out, the delete page lists the steps and signs in back',
      (tester) async {
    final api = _Server().client();
    await api.loadAuthConfig();
    final returns = <String>[];
    await _pump(
      tester,
      PrivacyPage(
        api: api,
        strings: const Strings(AppLanguage.en),
        page: WebPage.deleteAccount,
        web: PrivacyWebSession(
          user: null,
          consentRequired: false,
          onSignIn: (returnTo) async => returns.add(returnTo),
          onSessionChanged: (_) {},
          onDeleted: () {},
        ),
      ),
    );
    expect(find.text('Delete your 217 account'), findsOneWidget);
    expect(find.textContaining('tap Advanced options'), findsOneWidget);
    expect(find.text('What is deleted'), findsOneWidget);
    expect(find.text('What is kept'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('privacy-sign-in')));
    await tester.pumpAndSettle();
    expect(returns, ['/app/account/delete?lang=en']);
  });

  testWidgets('a stale sign-in asks to sign in again, back on the warning',
      (tester) async {
    final server = _Server(recent: false);
    final api = server.client();
    final returns = <String>[];
    await _pump(
      tester,
      PrivacyPage(
        api: api,
        strings: const Strings(AppLanguage.pt),
        web: PrivacyWebSession(
          user: _user,
          consentRequired: false,
          onSignIn: (returnTo) async => returns.add(returnTo),
          onSessionChanged: (_) {},
          onDeleted: () {},
        ),
      ),
    );
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('privacy-delete')),
        matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    expect(find.text('Excluir sua conta?'), findsOneWidget);
    expect(find.text('Entrar de novo para continuar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();
    expect(returns, ['/app/privacy?lang=pt&confirm=delete']);
    expect(server.calls, isNot(contains('DELETE /api/account')));
  });

  testWidgets('after a recent sign-in, delete and download run here',
      (tester) async {
    final server = _Server();
    final api = server.client();
    var deleted = 0;
    final downloads = <String>[];
    await _pump(
      tester,
      PrivacyPage(
        api: api,
        strings: const Strings(AppLanguage.en),
        download: (name, bytes, mime) {
          downloads.add('$name ${utf8.decode(bytes)}');
          return true;
        },
        web: PrivacyWebSession(
          user: _user,
          consentRequired: false,
          onSignIn: (_) async => fail('no sign-in needed'),
          onSessionChanged: (_) {},
          onDeleted: () => deleted++,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Download my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();
    expect(downloads, ['217-data-2026-11-02.json {"user":{}}']);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete account'));
    await tester.pumpAndSettle();
    // Cancel stays the prominent choice; nothing is deleted on it.
    await tester.tap(find.byKey(const ValueKey('privacy-cancel')));
    await tester.pumpAndSettle();
    expect(server.calls, isNot(contains('DELETE /api/account')));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();
    expect(server.calls, contains('DELETE /api/account'));
    expect(deleted, 1);
    expect(find.text('Your account and data were deleted.'), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy-delete')), findsNothing);
  });

  testWidgets('a server asking for a fresh sign-in sends the browser to it',
      (tester) async {
    final server = _Server(reauthOnDelete: true);
    final returns = <String>[];
    var deleted = 0;
    await _pump(
      tester,
      PrivacyPage(
        api: server.client(),
        strings: const Strings(AppLanguage.es),
        page: WebPage.deleteAccount,
        web: PrivacyWebSession(
          user: _user,
          consentRequired: false,
          onSignIn: (returnTo) async => returns.add(returnTo),
          onSessionChanged: (_) {},
          onDeleted: () => deleted++,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Eliminar cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();
    expect(returns, ['/app/account/delete?lang=es&confirm=delete']);
    expect(deleted, 0);
  });
}
