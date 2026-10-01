import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'settings advanced options + single language label ($brightness)',
      (tester) async {
        var portuguese = false;
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
                strings: Strings(portuguese),
                portuguese: portuguese,
                themeMode: ThemeMode.system,
                palette: AppPalette.azure,
                onPortugueseChanged: (pt) => setState(() => portuguese = pt),
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
        expect(find.byType(DropdownMenu<bool>), findsOneWidget);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.text('English'), findsWidgets);
        expect(find.text('Advanced options'), findsOneWidget);
        expect(find.text('Show more'), findsNothing);
        expect(find.text('API base URL'), findsNothing);
        expect(find.text('Test connection'), findsNothing);

        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();

        expect(find.text('Hide advanced options'), findsOneWidget);
        expect(find.text('API base URL'), findsWidgets);
        expect(find.text('Test connection'), findsOneWidget);

        // Open language dropdown menu and pick Português.
        await tester.tap(find.byType(DropdownMenu<bool>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Português').last);
        await tester.pumpAndSettle();

        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('IDIOMA'), findsOneWidget);
        expect(find.text('Idioma'), findsNothing);
        expect(find.text('Ocultar opções avançadas'), findsOneWidget);
        expect(find.text('Mostrar menos'), findsNothing);
      },
    );
  }
}
