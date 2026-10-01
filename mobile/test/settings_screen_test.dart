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
      'settings show-more reveals API; language is a dropdown ($brightness)',
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
        expect(find.text('LANGUAGE'), findsOneWidget);
        expect(find.byType(DropdownMenu<bool>), findsOneWidget);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.text('English'), findsWidgets);
        expect(find.text('Show more'), findsOneWidget);
        expect(find.text('Advanced'), findsNothing);
        expect(find.text('API base URL'), findsNothing);
        expect(find.text('Test connection'), findsNothing);

        await tester.tap(find.text('Show more'));
        await tester.pumpAndSettle();

        expect(find.text('Show less'), findsOneWidget);
        expect(find.text('API base URL'), findsWidgets);
        expect(find.text('Test connection'), findsOneWidget);

        // Open language dropdown menu and pick Português.
        await tester.tap(find.byType(DropdownMenu<bool>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Português').last);
        await tester.pumpAndSettle();

        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('Mostrar menos'), findsOneWidget);
      },
    );
  }
}
