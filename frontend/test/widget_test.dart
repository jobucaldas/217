import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/auth_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'auth screen brand + CTA readable ($brightness)',
      (tester) async {
        var openedServerSettings = false;
        final scheme = buildApp217ColorScheme(
          brightness,
          palette: AppPalette.blue,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: brightness,
              colorScheme: scheme,
              scaffoldBackgroundColor: scaffoldBackgroundFor(
                brightness,
                palette: AppPalette.blue,
              ),
            ),
            home: AuthScreen(
              strings: const Strings(AppLanguage.pt),
              onSignIn: () async {},
              onOpenSettings: () {},
              onOpenServerSettings: () => openedServerSettings = true,
            ),
          ),
        );

        expect(find.text('217'), findsOneWidget);
        expect(find.text('Entrar'), findsOneWidget);

        // Self-hosting tip: readable secondary text that opens Settings.
        final tip = find.byKey(const ValueKey('auth-self-host-tip'));
        expect(
          tester.widget<Text>(tip).data,
          'Tem seu próprio servidor 217? Configure em Ajustes.',
        );
        expect(tester.widget<Text>(tip).style?.color, scheme.onSurfaceVariant);
        await tester.tap(tip);
        expect(openedServerSettings, isTrue);
        expect(find.text('calendário de anticoncepcional'), findsOneWidget);
        expect(find.textContaining('tomada'), findsNothing);
        expect(find.text('EN'), findsNothing);
        expect(find.text('PT'), findsNothing);
        expect(find.byKey(const ValueKey('auth-settings')), findsOneWidget);
        // Default server is not surfaced on the first viewport.
        expect(find.byKey(const ValueKey('auth-custom-server')), findsNothing);

        final brand = tester.widget<Text>(find.text('217'));
        final cta = tester.widget<Text>(find.text('Entrar'));
        final tagline =
            tester.widget<Text>(find.text('calendário de anticoncepcional'));
        expect(brand.style?.color, scheme.onSurface);
        expect(tagline.style?.color, scheme.onSurfaceVariant);
        // FilledButton paints primary; label uses onPrimary via button theme.
        expect(cta.data, 'Entrar');

        // Settings sits where language used to (trailing / top-right).
        final settingsCenter =
            tester.getCenter(find.byKey(const ValueKey('auth-settings')));
        expect(settingsCenter.dx, greaterThan(300));

        // Brand cluster is visually centered (not top-weighted).
        final brandCenter = tester.getCenter(find.text('217'));
        final size = tester.getSize(find.byType(Scaffold).first);
        expect(brandCenter.dy, greaterThan(size.height * 0.28));
        expect(brandCenter.dy, lessThan(size.height * 0.62));
      },
    );
  }

  testWidgets('auth screen English tagline has no trailing period',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          strings: const Strings(AppLanguage.en),
          onSignIn: () async {},
          onOpenSettings: () {},
        ),
      ),
    );
    expect(find.text('contraceptive calendar'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  test('config defaults bake in no WorkOS client id', () {
    final config = AppConfig.fromEnvironment();
    expect(config.workosClientId, isEmpty);
    expect(config.redirectUri, 'com.jobucaldas.a217://auth/callback');
  });
}
