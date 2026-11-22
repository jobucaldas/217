import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/auth/device_key.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/screens/privacy_page.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/screens/sign_in_methods_section.dart';
import 'package:a217/src/theme/app_theme.dart';

/// A device key that never touches the platform channel: `create()` answers
/// a fake public key so password sign-in proceeds in widget tests.
class _FakeDeviceKey extends DeviceKey {
  @override
  Future<String?> create() async => 'fake-public-key';

  @override
  Future<void> delete() async {}
}

/// Auth config and the password endpoints, with the flags the test asks for.
class _Server {
  _Server({
    this.password = true,
    this.signup = true,
    this.workos = false,
    this.omitWorkosKey = false,
    this.fail = false,
    this.signupStatus = 201,
    this.loginStatus = 200,
    this.loginError = '',
    this.retryAfter,
    this.signupGate,
    this.verifyGate,
  });

  /// When set, /api/auth/config throws (unreachable server).
  final bool fail;

  /// When set, the config payload carries no `workos` key at all (a server
  /// older than PR #136).
  final bool omitWorkosKey;

  final bool password;
  final bool signup;
  final bool workos;
  final int signupStatus;
  int loginStatus;
  String loginError;
  final int? retryAfter;
  final Future<void>? signupGate;
  final Future<void>? verifyGate;
  final calls = <String>[];

  ApiClient client() => ApiClient(
        AppConfig(
          apiBaseUrl: 'https://217.example',
          workosClientId: '',
          redirectUri: 'com.caldasstudios.app217://auth/callback',
        ),
        deviceKey: _FakeDeviceKey(),
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          switch (request.url.path) {
            case '/api/auth/config':
              if (fail) throw http.ClientException('unreachable');
              return http.Response(
                jsonEncode({
                  'authkit': workos,
                  if (!omitWorkosKey) 'workos': workos,
                  'password': password,
                  'signup': signup,
                  'mail': false,
                }),
                200,
              );
            case '/api/auth/password/signup':
              await signupGate;
              return http.Response(
                  jsonEncode({'error': 'email already registered'}), signupStatus);
            case '/api/auth/password/verify':
              await verifyGate;
              return http.Response('{}', 200);
            case '/api/auth/password/login':
              if (loginStatus != 200) {
                return http.Response(
                  jsonEncode({'error': loginError}),
                  loginStatus,
                  headers: {
                    if (retryAfter != null) 'retry-after': '$retryAfter',
                  },
                );
              }
              return http.Response(
                jsonEncode({
                  'session_token': 'tok',
                  'user': {
                    'id': 'u1',
                    'email': 'user@example.com',
                    'name': 'User',
                    'role': 'owner',
                  },
                }),
                200,
              );
            case '/api/auth/session':
              return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'u1',
                    'email': 'user@example.com',
                    'name': 'User',
                    'role': 'owner',
                  },
                  'consent': {'version': 1, 'required': false},
                }),
                200,
              );
            case '/api/account/password':
              if (request.method == 'PUT') {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                if (body['current_password'] == 'wrong-current-pass') {
                  return http.Response(
                      jsonEncode({'error': 'current password is wrong'}), 403);
                }
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode({'error': 'set up another sign-in method first'}),
                409,
              );
          }
          return http.Response('{}', 404);
        }),
      );
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(brightness: Brightness.light),
    home: page,
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('server check accepts password or AuthKit', () async {
    expect(await _Server().client().checkServer(), ServerCheck.ok);
    expect(await _Server(password: false, workos: true).client().checkServer(),
        ServerCheck.ok);
    expect(await _Server(password: false).client().checkServer(),
        ServerCheck.signInNotConfigured);
  });

  testWidgets('privacy reauth uses password when both methods are enabled',
      (tester) async {
    final api = _Server(workos: true).client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      PrivacyPage(
        api: api,
        strings: const Strings(AppLanguage.en),
        web: PrivacyWebSession(
          user: const User(id: 'u1', email: 'user@example.com', name: 'User',
              role: 'owner', hasPassword: true),
          consentRequired: false,
          onSignIn: (_) async => fail('should use password re-entry'),
          onSessionChanged: (_) {},
          onDeleted: () {},
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reauth-password')), findsOneWidget);
  });

  testWidgets('password-only server: email form, no WorkOS button',
      (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-to-signup')), findsOneWidget);
    // WorkOS is off: no divider and no AuthKit button.
    expect(find.byKey(const ValueKey('auth-sign-in')), findsNothing);
    expect(find.text('or'), findsNothing);
  });

  testWidgets('signup disabled hides the create-account toggle', (tester) async {
    final server = _Server(signup: false);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    expect(find.byKey(const ValueKey('auth-to-signup')), findsNothing);
    expect(find.text('Create account'), findsNothing);
  });

  testWidgets('workos-only server keeps the old screen unchanged',
      (tester) async {
    final server = _Server(password: false, workos: true);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
        onSignInWorkOS: () async {},
      ),
    );
    expect(find.byKey(const ValueKey('auth-sign-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    expect(find.byKey(const ValueKey('auth-password')), findsNothing);
    expect(find.text('or'), findsNothing);
  });

  testWidgets('both on: password form above the WorkOS button, divided',
      (tester) async {
    final server = _Server(workos: true);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
        onSignInWorkOS: () async {},
      ),
    );
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-sign-in')), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
  });

  testWidgets(
      'workos:false shows no WorkOS button or divider even with the callback',
      (tester) async {
    final server = _Server(workos: false);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
        onSignInWorkOS: () async {},
      ),
    );
    expect(find.byKey(const ValueKey('auth-sign-in')), findsNothing);
    expect(find.text('or'), findsNothing);
  });

  testWidgets(
      'workos defaults to true when the config has no workos key (old server)',
      (tester) async {
    final server = _Server(workos: true, omitWorkosKey: true);
    final api = server.client();
    await api.loadAuthConfig();
    expect(api.workos, isTrue);
  });

  testWidgets('authkit false hides WorkOS (server without WorkOS credentials)',
      (tester) async {
    final server = _Server(workos: false, omitWorkosKey: true);
    final api = server.client();
    await api.loadAuthConfig();
    expect(api.workos, isFalse);
  });

  testWidgets('a config fetch failure still shows WorkOS sign-in',
      (tester) async {
    final server = _Server(workos: false, omitWorkosKey: true, fail: true);
    final api = server.client();
    await api.loadAuthConfig();
    expect(api.workos, isTrue);
  });

  testWidgets('a 401 login shows the wrong-credentials error', (tester) async {
    final server = _Server(loginStatus: 401, loginError: 'bad credentials');
    final api = server.client();
    await api.loadAuthConfig();
    var signedIn = 0;
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async => signedIn++,
      ),
    );
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), 'long-enough-password');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-error')), findsOneWidget);
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(signedIn, 0);
  });

  testWidgets('a 409 on sign-up says the email is taken', (tester) async {
    final server = _Server(signupStatus: 409);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    // Switch to create account first.
    await tester.tap(find.byKey(const ValueKey('auth-to-signup')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), 'long-enough-password');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('This email already has an account. Sign in instead.'),
        findsOneWidget);
    expect(server.calls, isNot(contains('POST /api/auth/password/login')));
  });

  testWidgets('a 429 shows the retry-after seconds', (tester) async {
    final server = _Server(loginStatus: 429, loginError: 'too many attempts',
        retryAfter: 42);
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), 'long-enough-password');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Too many attempts. Try again in 42 s.'), findsOneWidget);
  });

  testWidgets('a short password is refused before any request', (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), 'short');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 15 characters.'), findsOneWidget);
    expect(server.calls, isNot(contains('POST /api/auth/password/login')));
  });

  testWidgets('a 403 verify answer switches to the code entry', (tester) async {
    final server = _Server(
        loginStatus: 403, loginError: 'verify your email to sign in');
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      AuthScreen(
        strings: const Strings(AppLanguage.en),
        api: api,
        onSignedIn: (_) async {},
      ),
    );
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), 'long-enough-password');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('verify-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('verify-resend')), findsOneWidget);
    expect(find.byKey(const ValueKey('verify-back')), findsOneWidget);
    // Back returns to the form.
    await tester.tap(find.byKey(const ValueKey('verify-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
  });

  testWidgets('verification is not repeated after login fails', (tester) async {
    final server = _Server(
        loginStatus: 403, loginError: 'verify your email to sign in');
    final api = server.client();
    await api.loadAuthConfig();
    var signedIn = 0;
    await _pump(tester, AuthScreen(
      strings: const Strings(AppLanguage.en), api: api,
      onSignedIn: (_) async => signedIn++,
    ));
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'user@example.com');
    await tester.enterText(find.byKey(const ValueKey('auth-password')), 'long-enough-password');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    server.loginStatus = 500;
    await tester.enterText(find.byKey(const ValueKey('verify-code')), '123456');
    await tester.tap(find.byKey(const ValueKey('verify-submit')));
    await tester.pumpAndSettle();
    server.loginStatus = 200;
    await tester.tap(find.byKey(const ValueKey('verify-submit')));
    await tester.pumpAndSettle();
    expect(server.calls.where((call) => call == 'POST /api/auth/password/verify').length, 1);
    expect(signedIn, 1);
  });

  for (final duringVerify in [false, true]) {
    testWidgets('server switch during ${duringVerify ? 'verification' : 'signup'} blocks login',
        (tester) async {
      final gate = Completer<void>();
      final server = _Server(
        signupGate: duringVerify ? null : gate.future,
        verifyGate: duringVerify ? gate.future : null,
        loginStatus: duringVerify ? 403 : 200,
        loginError: 'verify your email to sign in',
      );
      final api = server.client();
      await api.loadAuthConfig();
      await _pump(tester, AuthScreen(
        strings: const Strings(AppLanguage.en), api: api,
        onSignedIn: (_) async => fail('must not sign in'),
      ));
      if (!duringVerify) {
        await tester.tap(find.byKey(const ValueKey('auth-to-signup')));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const ValueKey('auth-email')), 'user@example.com');
      await tester.enterText(find.byKey(const ValueKey('auth-password')), 'long-enough-password');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pump();
      if (duringVerify) {
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('verify-code')), '123456');
        await tester.tap(find.byKey(const ValueKey('verify-submit')));
        await tester.pump();
      }
      await api.setApiBaseUrl('https://other.example');
      gate.complete();
      await tester.pumpAndSettle();
      expect(server.calls.where((call) => call == 'POST /api/auth/password/login').length,
          duringVerify ? 1 : 0);
    });
  }

  testWidgets('settings shows Set password without one, and Remove with',
      (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    Widget page(User user) => SettingsPage(
          api: api,
          strings: const Strings(AppLanguage.en),
          language: AppLanguage.en,
          onLanguageChanged: (_) {},
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          palette: AppPalette.blue,
          onPaletteChanged: (_) {},
          onApiBaseChanged: () {},
          user: user,
          share: const ShareState(status: 'none'),
          onLogout: () async {},
        );
    await _pump(
      tester,
      page(const User(
        id: 'u1',
        email: 'user@example.com',
        name: 'User',
        role: 'owner',
      )),
    );
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Set password'),
      200,
      scrollable: scroll,
    );
    expect(find.text('Remove password'), findsNothing);

    await _pump(
      tester,
      page(const User(
        id: 'u1',
        email: 'user@example.com',
        name: 'User',
        role: 'owner',
        hasPassword: true,
      )),
    );
    final scroll2 = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Remove password'),
      200,
      scrollable: scroll2,
    );
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('change password: wrong current password shows inline',
      (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      SignInMethodsSection(
        api: api,
        strings: const Strings(AppLanguage.en),
        user: const User(
          id: 'u1',
          email: 'user@example.com',
          name: 'User',
          role: 'owner',
          hasPassword: true,
        ),
        group: (children) => Scaffold(body: Column(children: children)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('password-current')), 'wrong-current-pass');
    await tester.enterText(
        find.byKey(const ValueKey('password-new')), 'a-brand-new-password');
    await tester.enterText(
        find.byKey(const ValueKey('password-confirm')), 'a-brand-new-password');
    await tester.tap(find.byKey(const ValueKey('password-save')));
    await tester.pumpAndSettle();
    expect(find.text('Current password is wrong.'), findsOneWidget);
  });

  testWidgets('remove password: 409 says to set up another method first',
      (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      SignInMethodsSection(
        api: api,
        strings: const Strings(AppLanguage.en),
        user: const User(
          id: 'u1',
          email: 'user@example.com',
          name: 'User',
          role: 'owner',
          hasPassword: true,
        ),
        group: (children) => Scaffold(body: Column(children: children)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-remove-password')));
    await tester.pumpAndSettle();
    expect(find.text('Remove password?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-password-cancel')));
    await tester.pumpAndSettle();
    expect(server.calls, isNot(contains('DELETE /api/account/password')));

    await tester.tap(find.byKey(const ValueKey('settings-remove-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-password-confirm')));
    await tester.pumpAndSettle();
    expect(server.calls, contains('DELETE /api/account/password'));
    expect(
      find.text('Set up another sign-in method before removing the password.'),
      findsOneWidget,
    );
  });

  testWidgets('remove-password dialog text is generic about WorkOS',
      (tester) async {
    final server = _Server();
    final api = server.client();
    await api.loadAuthConfig();
    await _pump(
      tester,
      SignInMethodsSection(
        api: api,
        strings: const Strings(AppLanguage.en),
        user: const User(
          id: 'u1',
          email: 'user@example.com',
          name: 'User',
          role: 'owner',
          hasPassword: true,
        ),
        group: (children) => Scaffold(body: Column(children: children)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-remove-password')));
    await tester.pumpAndSettle();
    expect(
      find.text('You will no longer be able to sign in with a password.'),
      findsOneWidget,
    );
    expect(find.textContaining('WorkOS'), findsNothing);
  });
}
