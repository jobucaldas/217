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
              server: '217.caldas-studios.com.br',
              onOpenServerSettings: () => openedServerSettings = true,
            ),
          ),
        );

        expect(find.text('217'), findsOneWidget);
        expect(find.text('Entrar'), findsOneWidget);

        // Server link: small muted text at the bottom that opens Settings.
        final server = find.text('Servidor: 217.caldas-studios.com.br');
        expect(
          tester.widget<Text>(server).style?.color,
          scheme.onSurfaceVariant,
        );
        expect(
          tester.getCenter(server).dy,
          greaterThan(tester.getBottomLeft(find.text('Entrar')).dy + 100),
        );
        await tester.tap(server);
        expect(openedServerSettings, isTrue);
        expect(find.text('Calendário de Remédios'), findsOneWidget);
        expect(find.textContaining('tomada'), findsNothing);
        expect(find.text('EN'), findsNothing);
        expect(find.text('PT'), findsNothing);
        expect(find.byKey(const ValueKey('auth-settings')), findsOneWidget);

        final brand = tester.widget<Text>(find.text('217'));
        final cta = tester.widget<Text>(find.text('Entrar'));
        final tagline =
            tester.widget<Text>(find.text('Calendário de Remédios'));
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

  test('config defaults bake in no WorkOS client id', () {
    final config = AppConfig.fromEnvironment();
    expect(config.workosClientId, isEmpty);
    expect(config.redirectUri, 'com.caldasstudios.app217://auth/callback');
  });
}
