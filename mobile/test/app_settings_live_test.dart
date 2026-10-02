import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/settings_screen.dart';

ApiClient _signedOutApi() => ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient(
        (_) async => http.Response('{"user":null,"share":null}', 200),
      ),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  _pendingInviteTests();

  testWidgets('settings route follows theme + language changes live',
      (tester) async {
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    // No saved language and an en_US test device → English.
    expect(find.text('Sign in'), findsOneWidget);
    // The self-host card is a web thing; Android links to Settings instead.
    expect(find.byKey(const ValueKey('auth-self-host-card')), findsNothing);
    expect(find.byKey(const ValueKey('auth-self-host-tip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-settings')));
    await tester.pumpAndSettle();

    // Signed out: no account actions to show.
    expect(find.text('Delete account'), findsNothing);
    expect(find.text('Log out'), findsNothing);

    SegmentedButton<ThemeMode> themeToggle() =>
        tester.widget(find.byType(SegmentedButton<ThemeMode>));
    expect(themeToggle().selected, {ThemeMode.system});

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(themeToggle().selected, {ThemeMode.dark});
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byType(DropdownMenu<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    // The open Settings page itself switches language, not only home.
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Escuro'), findsOneWidget);
    expect(await const FlutterSecureStorage().read(key: 'language'), 'pt');
  });

  testWidgets('saved language survives a restart', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'language': 'pt'});
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);
  });

  Future<void> pumpWithDeviceLocales(
    WidgetTester tester,
    List<Locale> locales,
  ) async {
    tester.platformDispatcher.localesTestValue = locales;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
  }

  testWidgets('no saved language: follows a Portuguese device',
      (tester) async {
    await pumpWithDeviceLocales(tester, const [Locale('pt', 'BR')]);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('no saved language: first supported device language wins',
      (tester) async {
    await pumpWithDeviceLocales(
      tester,
      const [Locale('fr', 'FR'), Locale('es', 'MX'), Locale('pt', 'BR')],
    );
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('no saved language: unsupported device falls back to English',
      (tester) async {
    await pumpWithDeviceLocales(tester, const [Locale('de', 'DE')]);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a saved language beats the device language', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'language': 'en'});
    await pumpWithDeviceLocales(tester, const [Locale('pt', 'BR')]);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('Spanish can be saved and restored', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'language': 'es'});
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('calendario de anticonceptivos'), findsOneWidget);
  });

  testWidgets('self-host tip opens Settings at the server field',
      (tester) async {
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auth-self-host-tip')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('server-url')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Self-hosted server URL'), findsOneWidget);
  });

  testWidgets('custom server host is shown on the sign-in screen',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'api_base_url': 'https://self.example.com:8443',
    });
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
    expect(find.text('Server: self.example.com:8443'), findsOneWidget);
  });
}

/// Signed-in owner with nothing shared; accepting an invite turns them into
/// a partner viewing the owner's calendar.
class _InviteServer {
  bool joined = false;
  String? acceptedCode;

  ApiClient client() => ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/auth/session') {
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u1',
                  'email': 'bf@example.com',
                  'name': 'BF',
                  'role': joined ? 'partner' : 'owner',
                },
                'share': joined
                    ? {
                        'status': 'active',
                        'owner_name': 'Her',
                        'can_edit_calendar': false,
                      }
                    : {'status': 'none', 'can_edit_calendar': true},
              }),
              200,
            );
          }
          if (path == '/api/share/accept') {
            acceptedCode = (jsonDecode(request.body) as Map)['code'] as String;
            joined = true;
            return http.Response(
              jsonEncode({
                'status': 'active',
                'owner_name': 'Her',
                'can_edit_calendar': false,
              }),
              200,
            );
          }
          if (path == '/api/entries') {
            return http.Response('{"entries":[]}', 200);
          }
          return http.Response('{"error":"not found"}', 404);
        }),
      );
}

void _pendingInviteTests() {
  testWidgets('opened invite link offers to join after sign-in',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pending_invite': 'ABCD1234'});
    final server = _InviteServer();
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Join the shared calendar?'), findsOneWidget);
    expect(find.textContaining('ABCD1234'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pending-invite-join')));
    await tester.pumpAndSettle();

    expect(server.acceptedCode, 'ABCD1234');
    expect(find.text('Read-only calendar'), findsOneWidget);
    expect(
      await const FlutterSecureStorage().read(key: 'pending_invite'),
      isNull,
    );
  });

  testWidgets('declining the invite prompt forgets the code', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pending_invite': 'ABCD1234'});
    final server = _InviteServer();
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(server.acceptedCode, isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'pending_invite'),
      isNull,
    );
  });
}
