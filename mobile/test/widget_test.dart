import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/auth_screen.dart';

void main() {
  testWidgets('auth screen shows brand and WorkOS CTA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          strings: const Strings(true),
          onSignIn: () async {},
          onToggleLanguage: () {},
        ),
      ),
    );
    expect(find.text('217'), findsOneWidget);
    expect(find.text('Continuar com WorkOS'), findsOneWidget);
  });

  test('config defaults expose public WorkOS client id only', () {
    final config = AppConfig.fromEnvironment();
    expect(config.workosClientId.startsWith('client_'), isTrue);
    expect(config.redirectUri, 'com.jobucaldas.a217://auth/callback');
  });
}
