import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/screens/settings_screen.dart';

ApiClient _signedOutApi() => ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient(
        (_) async => http.Response('{"user":null,"share":null}', 200),
      ),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('settings route follows theme + language changes live',
      (tester) async {
    final api = _signedOutApi();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    // Test devices report en_US → English on first launch.
    expect(find.text('Sign in'), findsOneWidget);
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

    await tester.tap(find.byType(DropdownMenu<bool>));
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
