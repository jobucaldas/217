import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/server_setup_screen.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';
import 'package:a217/src/theme/contrast.dart';

/// A release APK: no server baked in.
AppConfig _noServer() => AppConfig(
      apiBaseUrl: '',
      workosClientId: 'client_build',
      redirectUri: 'com.jobucaldas.a217://auth/callback',
    );

/// Fake 217 servers keyed by host; anything else is unreachable.
class _Servers {
  final requests = <Uri>[];
  final configs = <String, String>{
    'self.example.com': '{"authkit":true,"password":false}',
    'other.example.com': '{"authkit":true,"password":false}',
    'nosignin.example.com': '{"authkit":false,"password":false}',
  };

  MockClient get client => MockClient((request) async {
        requests.add(request.url);
        final config = configs[request.url.host];
        if (config == null) throw const SocketException('no route');
        if (request.url.path == '/api/auth/config') {
          return http.Response(config, 200);
        }
        if (request.url.path == '/api/auth/session') {
          return http.Response('{"user":null,"share":null}', 200);
        }
        return http.Response('not found', 404);
      });
}

Future<void> _pumpApp(
  WidgetTester tester,
  ApiClient api, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  if (themeMode == ThemeMode.dark) {
    await const FlutterSecureStorage().write(key: 'theme_mode', value: 'dark');
  }
  await tester.pumpWidget(App217(config: api.config, api: api));
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester, String address) async {
  await tester.enterText(
    find.byKey(const ValueKey('server-setup-address')),
    address,
  );
  await tester.tap(find.byKey(const ValueKey('server-setup-connect')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('release builds have no default server; web and debug do', () {
    expect(_noServer().hasDefaultServer, isFalse);
    expect(_noServer().needsServerSetup, isTrue);
    // Tests run as a debug build: the emulator default stays.
    final debug = AppConfig.fromEnvironment();
    expect(debug.hasDefaultServer, isTrue);
    expect(debug.needsServerSetup, isFalse);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('first launch asks for a server before sign-in ($mode)',
        (tester) async {
      final servers = _Servers();
      final api = ApiClient(_noServer(), httpClient: servers.client);
      await _pumpApp(tester, api, themeMode: mode);

      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.text('Connect to your server'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      // Nothing to ask a server that isn't set up yet.
      expect(servers.requests, isEmpty);

      // Readable in both themes: title, explanation and field label.
      final context = tester.element(find.byType(ServerSetupScreen));
      final theme = Theme.of(context);
      expect(theme.brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      final background = theme.scaffoldBackgroundColor;
      for (final label in [
        'Connect to your server',
        "Enter the server's address, or paste an invite link you got.",
      ]) {
        final color = tester.widget<Text>(find.text(label)).style!.color!;
        expect(contrastRatio(color, background), greaterThanOrEqualTo(4.5),
            reason: label);
      }
      final cta = tester.widget<FilledButton>(
        find.byKey(const ValueKey('server-setup-connect')),
      );
      expect(cta.onPressed, isNotNull);
      expect(find.byKey(const ValueKey('server-setup-guide')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-setup-settings')), findsOneWidget);
    });
  }

  testWidgets('connecting checks the server, then shows sign-in for it',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'old-build'});
    final servers = _Servers();
    final api = ApiClient(_noServer(), httpClient: servers.client);
    await _pumpApp(tester, api);

    await _connect(tester, 'not a url');
    expect(find.text('Enter an address like 217.example.com'), findsOneWidget);

    await _connect(tester, 'down.example.com');
    expect(
      find.text("Can't reach that address. Check it and your connection."),
      findsOneWidget,
    );
    await _connect(tester, 'nosignin.example.com');
    expect(find.text("That server hasn't set up sign-in yet"), findsOneWidget);
    expect(find.byType(ServerSetupScreen), findsOneWidget);

    await _connect(tester, 'self.example.com');
    expect(find.byType(ServerSetupScreen), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Server: self.example.com'), findsOneWidget);
    expect(api.config.apiBaseUrl, 'https://self.example.com');
    expect(
      await const FlutterSecureStorage().read(key: 'api_base_url'),
      'https://self.example.com',
    );
    // A token from an older build is never sent to the new server.
    expect(await const FlutterSecureStorage().read(key: 'session_token'),
        isNull);
  });

  testWidgets('a pasted invite link sets the server and keeps the invite',
      (tester) async {
    final api = ApiClient(_noServer(), httpClient: _Servers().client);
    await _pumpApp(tester, api);

    await _connect(tester, 'https://self.example.com/?invite=ABCD2345');

    expect(find.text('Server: self.example.com'), findsOneWidget);
    expect(api.config.apiBaseUrl, 'https://self.example.com');
    expect(
      await const FlutterSecureStorage().read(key: 'pending_invite'),
      'ABCD2345',
    );
  });

  testWidgets('the saved server survives a restart', (tester) async {
    FlutterSecureStorage.setMockInitialValues(
      {'api_base_url': 'https://self.example.com'},
    );
    final servers = _Servers();
    final api = ApiClient(_noServer(), httpClient: servers.client);
    await _pumpApp(tester, api);

    expect(find.byType(ServerSetupScreen), findsNothing);
    expect(find.text('Server: self.example.com'), findsOneWidget);
    expect(servers.requests.single.path, '/api/auth/session');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('signed out, the server link switches servers ($mode)',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues(
        {'api_base_url': 'https://self.example.com'},
      );
      final api = ApiClient(_noServer(), httpClient: _Servers().client);
      await _pumpApp(tester, api, themeMode: mode);

      await tester.tap(find.text('Server: self.example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Change server'), findsOneWidget);
      final field = find.byKey(const ValueKey('server-setup-address'));
      expect(tester.widget<TextField>(field).controller!.text,
          'https://self.example.com');
      final note = find.textContaining('sign in again after switching');
      final background =
          Theme.of(tester.element(field)).scaffoldBackgroundColor;
      expect(
        contrastRatio(tester.widget<Text>(note).style!.color!, background),
        greaterThanOrEqualTo(4.5),
      );

      // Same server: nothing changes.
      await tester.tap(find.byKey(const ValueKey('server-setup-connect')));
      await tester.pumpAndSettle();
      expect(find.text('Change server'), findsNothing);
      expect(find.text('Server: self.example.com'), findsOneWidget);

      await tester.tap(find.text('Server: self.example.com'));
      await tester.pumpAndSettle();
      await _connect(tester, 'other.example.com');
      expect(find.text('Change server'), findsNothing);
      expect(find.text('Server: other.example.com'), findsOneWidget);
      expect(api.config.apiBaseUrl, 'https://other.example.com');

      // Back from the change screen keeps the current server.
      await tester.tap(find.text('Server: other.example.com'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Server: other.example.com'), findsOneWidget);
    });
  }

  testWidgets('settings on the setup screen skip the server field',
      (tester) async {
    final api = ApiClient(_noServer(), httpClient: _Servers().client);
    await _pumpApp(tester, api);

    await tester.tap(find.byKey(const ValueKey('server-setup-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Advanced options'), findsNothing);
    expect(find.byKey(const ValueKey('server-url')), findsNothing);

    // Language picked there applies to the setup screen.
    await tester.tap(find.byType(DropdownMenu<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Conecte ao seu servidor'), findsOneWidget);
  });

  testWidgets('release builds ask for https://', (tester) async {
    final servers = _Servers();
    final api = ApiClient(_noServer(), httpClient: servers.client);
    var connected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: ServerSetupScreen(
          api: api,
          strings: const Strings(AppLanguage.en),
          onConnected: ({required changed, inviteCode}) => connected++,
          onOpenGuide: () {},
          requireHttps: true,
        ),
      ),
    );

    await _connect(tester, 'http://self.example.com');
    expect(find.text('The app only connects to https:// addresses'),
        findsOneWidget);
    expect(servers.requests, isEmpty);
    expect(connected, 0);

    await _connect(tester, 'self.example.com');
    expect(connected, 1);
  });
}
