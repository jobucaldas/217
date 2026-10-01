import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/i18n.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('day sheet has no intake prompt copy ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: brightness,
            palette: AppPalette.azure,
          ),
          home: const Scaffold(
            body: DayEditorSheet(
              strings: Strings(false),
              date: '2026-10-01',
              initialTaken: null,
              initialNotes: '',
              hadEntry: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('How did intake go?'), findsNothing);
      expect(find.text('Como foi a tomada?'), findsNothing);
      expect(find.text('Taken'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  }
}
