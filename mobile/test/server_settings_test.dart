import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

const _default = 'https://default.example.com';

AppConfig _config() => AppConfig(
      apiBaseUrl: _default,
      workosClientId: 'client_test',
      redirectUri: 'com.jobucaldas.a217://auth/callback',
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('ApiClient server URL', () {
    test('parseApiBase trims and rejects non-http(s) or host-less URLs', () {
      expect(ApiClient.parseApiBase('  https://a.example/// '),
          'https://a.example');
      expect(ApiClient.parseApiBase(''), '');
      expect(() => ApiClient.parseApiBase('a.example'), throwsFormatException);
      expect(() => ApiClient.parseApiBase('ftp://a.example'),
          throwsFormatException);
      expect(() => ApiClient.parseApiBase('https://'), throwsFormatException);
    });

    test('custom server persists; switching drops the old session token',
        () async {
      final api = ApiClient(_config());
      await api.saveSessionToken('old-token');

      expect(await api.setApiBaseUrl('https://self.example.com/'), isTrue);
      expect(api.config.apiBaseUrl, 'https://self.example.com');
      expect(api.config.usesCustomApiBase, isTrue);
      expect(await api.readSessionToken(), isNull);

      final reloaded = ApiClient(_config());
      await reloaded.loadPersistedApiBase();
      expect(reloaded.config.apiBaseUrl, 'https://self.example.com');
    });

    test('empty URL resets to the build default, not to no server', () async {
      final api = ApiClient(_config());
      await api.setApiBaseUrl('https://self.example.com');
      await api.saveSessionToken('self-token');

      expect(await api.setApiBaseUrl('   '), isTrue);
      expect(api.config.apiBaseUrl, _default);
      expect(api.config.usesCustomApiBase, isFalse);
      expect(await api.readSessionToken(), isNull);

      final reloaded = ApiClient(_config());
      await reloaded.loadPersistedApiBase();
      expect(reloaded.config.apiBaseUrl, _default);
    });

    test('saving the current server keeps the session', () async {
      final api = ApiClient(_config());
      await api.saveSessionToken('token');
      expect(await api.setApiBaseUrl(_default), isFalse);
      expect(await api.readSessionToken(), 'token');
    });

    test('legacy empty stored value falls back to the default', () async {
      FlutterSecureStorage.setMockInitialValues({'api_base_url': ''});
      final api = ApiClient(_config());
      await api.loadPersistedApiBase();
      expect(api.config.apiBaseUrl, _default);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('self-hosted server field validates and saves ($brightness)',
        (tester) async {
      final api = ApiClient(_config());
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: brightness,
            palette: AppPalette.azure,
          ),
          home: SettingsPage(
            api: api,
            strings: const Strings(false),
            portuguese: false,
            themeMode: ThemeMode.system,
            palette: AppPalette.azure,
            onPortugueseChanged: (_) {},
            onThemeModeChanged: (_) {},
            onPaletteChanged: (_) {},
            onApiBaseChanged: () => changes++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Advanced options'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();

      // Copy speaks to self-hosters, not to local emulator setups.
      expect(find.text('Self-hosted server URL'), findsOneWidget);
      expect(find.textContaining('host your own 217 server'), findsOneWidget);
      expect(find.textContaining('10.0.2.2'), findsNothing);
      expect(find.textContaining('LAN'), findsNothing);
      // Default server leaves the field empty.
      final field = find.byKey(const ValueKey('server-url'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);

      await tester.enterText(field, 'not a url');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a full address'), findsOneWidget);
      expect(changes, 0);

      await tester.enterText(field, 'https://self.example.com/');
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a full address'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Server saved'), findsOneWidget);
      expect(api.config.apiBaseUrl, 'https://self.example.com');
      expect(changes, 1);

      await tester.enterText(field, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Using the default server'), findsOneWidget);
      expect(api.config.apiBaseUrl, _default);
      expect(changes, 2);
    });
  }

  testWidgets('advanced options start open when a custom server is set',
      (tester) async {
    final api = ApiClient(_config());
    await api.setApiBaseUrl('https://self.example.com');
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          api: api,
          strings: const Strings(true),
          portuguese: true,
          themeMode: ThemeMode.system,
          palette: AppPalette.azure,
          onPortugueseChanged: (_) {},
          onThemeModeChanged: (_) {},
          onPaletteChanged: (_) {},
          onApiBaseChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('server-url')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('URL do servidor próprio'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('server-url')))
          .controller!
          .text,
      'https://self.example.com',
    );
  });
}
