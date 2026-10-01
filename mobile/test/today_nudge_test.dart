import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/today_nudge.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('today nudge visible when unrecorded ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: Scaffold(
            body: TodayNudge(
              strings: const Strings(true),
              todayEntry: null,
              onRecord: () {},
            ),
          ),
        ),
      );
      expect(find.text('Registrar hoje'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    });

    testWidgets('today nudge hidden after registration ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: Scaffold(
            body: TodayNudge(
              strings: const Strings(true),
              todayEntry: const Entry(
                date: '2026-10-01',
                taken: true,
                notes: '',
              ),
              onRecord: () {},
            ),
          ),
        ),
      );
      expect(find.text('Registrar hoje'), findsNothing);
      expect(find.text('Atualizar hoje'), findsNothing);
    });
  }
}
