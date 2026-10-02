import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'settings advanced options + single language label ($brightness)',
      (tester) async {
        var language = AppLanguage.en;
        final api = ApiClient(AppConfig.fromEnvironment());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.azure,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => SettingsPage(
                api: api,
                strings: Strings(language),
                language: language,
                themeMode: ThemeMode.system,
                palette: AppPalette.azure,
                onLanguageChanged: (l) => setState(() => language = l),
                onThemeModeChanged: (_) {},
                onPaletteChanged: (_) {},
                onApiBaseChanged: () {},
                onLogout: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        // Section label only — not duplicated as DropdownMenu floating label.
        expect(find.text('LANGUAGE'), findsOneWidget);
        expect(find.text('Language'), findsNothing);
        expect(find.byType(DropdownMenu<AppLanguage>), findsOneWidget);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.text('English'), findsWidgets);
        expect(find.text('Advanced options'), findsOneWidget);
        expect(find.text('Show more'), findsNothing);
        expect(find.text('Self-hosted server URL'), findsNothing);
        expect(find.text('Test connection'), findsNothing);

        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();

        expect(find.text('Hide advanced options'), findsOneWidget);
        expect(find.text('Self-hosted server URL'), findsWidgets);
        expect(find.text('Test connection'), findsOneWidget);

        // Open language dropdown menu and pick Português.
        await tester.tap(find.byType(DropdownMenu<AppLanguage>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Português').last);
        await tester.pumpAndSettle();

        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('IDIOMA'), findsOneWidget);
        expect(find.text('Idioma'), findsNothing);
        expect(find.text('Ocultar opções avançadas'), findsOneWidget);
        expect(find.text('Mostrar menos'), findsNothing);

        await tester.tap(find.byType(DropdownMenu<AppLanguage>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Español').last);
        await tester.pumpAndSettle();
        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('IDIOMA'), findsOneWidget);
        expect(find.text('Ocultar opciones avanzadas'), findsOneWidget);
      },
    );
  }

  testWidgets('signed in: share, no server setting, delete near logout', (tester) async {
    final api = ApiClient(AppConfig.fromEnvironment());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: SettingsPage(
          api: api,
          strings: const Strings(AppLanguage.en),
          language: AppLanguage.en,
          themeMode: ThemeMode.system,
          palette: AppPalette.azure,
          onLanguageChanged: (_) {},
          onThemeModeChanged: (_) {},
          onPaletteChanged: (_) {},
          onApiBaseChanged: () {},
          user: const User(
            id: '1',
            email: 'a@b.c',
            name: 'Owner',
            role: 'owner',
          ),
          share: const ShareState(status: 'none'),
          onShareChanged: (_) {},
          onAccountDeleted: () {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    int textIndex(String label) {
      final texts = find.byType(Text).evaluate().toList();
      return texts.indexWhere(
        (e) => (e.widget as Text).data == label,
      );
    }

    await tester.scrollUntilVisible(
      find.text('Log out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final shareIdx = textIndex('SHARE CALENDAR WITH BOYFRIEND');
    final deleteIdx = textIndex('Delete account');
    final logoutIdx = textIndex('Log out');
    expect(shareIdx, greaterThanOrEqualTo(0));
    // The server is chosen before sign-in, so it is not offered here.
    expect(find.text('Advanced options'), findsNothing);
    expect(find.text('Self-hosted server URL'), findsNothing);
    expect(deleteIdx, greaterThan(shareIdx));
    expect(logoutIdx, greaterThan(deleteIdx));

    final deleteY = tester.getTopLeft(find.text('Delete account')).dy;
    final logoutY = tester.getTopLeft(find.text('Log out')).dy;
    expect(logoutY - deleteY, lessThan(80));

    final deleteLabel = tester.widget<Text>(find.text('Delete account'));
    final logoutLabel = tester.widget<Text>(find.text('Log out'));
    expect(deleteLabel.style?.color, const Color(0xFFDC2626));
    expect(logoutLabel.style?.color, const Color(0xFFEA580C));
  });
}
