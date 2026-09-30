import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/auth_screen.dart';

void main() {
  testWidgets('auth screen shows brand and single sign-in CTA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          strings: const Strings(true),
          apiBaseUrl: 'http://10.0.2.2:8787',
          onSignIn: () async {},
          onToggleLanguage: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    expect(find.text('217'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Seu calendário de tomada.'), findsOneWidget);
    // API base URL stays in Settings, not on the first viewport.
    expect(find.text('http://10.0.2.2:8787'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  test('config defaults expose public WorkOS client id only', () {
    final config = AppConfig.fromEnvironment();
    expect(config.workosClientId.startsWith('client_'), isTrue);
    expect(config.redirectUri, 'com.jobucaldas.a217://auth/callback');
  });
}
