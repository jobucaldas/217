import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/role_screen.dart';
import 'package:a217/src/theme/app_theme.dart';
import 'package:a217/src/theme/contrast.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final brightness in Brightness.values) {
    testWidgets('dialog title is readable on the dialog surface ($brightness)',
        (tester) async {
      final strings = Strings(AppLanguage.en);
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => confirmRoleSwitch(
                context: context,
                api: ApiClient(AppConfig.fromEnvironment()),
                strings: strings,
                role: 'partner',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final title = find.text(strings.switchToPartner);
      final context = tester.element(title);
      final resolved = DefaultTextStyle.of(context)
          .style
          .merge(tester.widget<Text>(title).style)
          .color!;
      final surface = tester
          .widget<Material>(find
              .descendant(
                  of: find.byType(AlertDialog), matching: find.byType(Material))
              .first)
          .color!;
      expect(meetsBodyContrast(resolved, surface), isTrue,
          reason: 'title $resolved on dialog surface $surface');
    });

    test('every text theme style is readable on the surface ($brightness)', () {
      final theme = buildApp217Theme(brightness: brightness);
      final styles = {
        'display': [
          theme.textTheme.displayLarge,
          theme.textTheme.displayMedium,
          theme.textTheme.displaySmall,
        ],
        'headline': [
          theme.textTheme.headlineLarge,
          theme.textTheme.headlineMedium,
          theme.textTheme.headlineSmall,
        ],
        'title': [
          theme.textTheme.titleLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.titleSmall,
        ],
        'body': [
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.bodySmall,
        ],
        'label': [
          theme.textTheme.labelLarge,
          theme.textTheme.labelMedium,
          theme.textTheme.labelSmall,
        ],
      };
      styles.forEach((group, list) {
        for (final style in list) {
          expect(meetsBodyContrast(style!.color!, theme.colorScheme.surface),
              isTrue,
              reason: '$group ${style.color} on ${theme.colorScheme.surface}');
        }
      });
    });
  }
}
