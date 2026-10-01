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
      'settings hides API until Advanced opens ($brightness)',
      (tester) async {
        final api = ApiClient(AppConfig.fromEnvironment());
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
              onToggleLanguage: () {},
              onThemeModeChanged: (_) {},
              onPaletteChanged: (_) {},
              onApiBaseChanged: () {},
              onLogout: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('APPEARANCE'), findsOneWidget);
        expect(find.text('ADVANCED'), findsOneWidget);
        expect(find.text('API base URL'), findsNothing);
        expect(find.text('Test connection'), findsNothing);

        await tester.tap(find.text('Advanced').hitTestable().first);
        await tester.pumpAndSettle();

        expect(find.text('API base URL'), findsWidgets);
        expect(find.text('Test connection'), findsOneWidget);

        // Section labels and body stay painted (smoke readability).
        final scheme = buildApp217ColorScheme(brightness);
        expect(scheme.onSurface, isNot(equals(scheme.surface)));
      },
    );
  }
}
