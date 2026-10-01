import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/today_nudge.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final brightness in Brightness.values) {
    testWidgets(
        'today nudge is text pill with connected plus when unrecorded ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: Scaffold(
            body: Stack(
              children: [
                TodayNudge(
                  strings: const Strings(true),
                  todayEntry: null,
                  onRecord: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Atualizar hoje'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byType(Positioned), findsWidgets);
      // Control is a text pill with corner plus, not a lone circular FAB.
      final size =
          tester.getSize(find.byKey(const ValueKey('today-nudge-control')));
      expect(size.width, greaterThan(TodayNudge.pillHeight));
      expect(size.height, TodayNudge.height);
      // Plus sits on the pill’s top-right corner (higher than pill midline).
      final plusCenter = tester.getCenter(find.byIcon(Icons.add));
      final controlTopLeft =
          tester.getTopLeft(find.byKey(const ValueKey('today-nudge-control')));
      expect(plusCenter.dy, lessThan(controlTopLeft.dy + TodayNudge.pillHeight / 2));
      expect(
        plusCenter.dx,
        greaterThan(controlTopLeft.dx + size.width * 0.55),
      );
    });

    testWidgets('today nudge shows Update today in English ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: Scaffold(
            body: Stack(
              children: [
                TodayNudge(
                  strings: const Strings(false),
                  todayEntry: null,
                  onRecord: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Update today'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('today nudge hidden after registration ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: Scaffold(
            body: Stack(
              children: [
                TodayNudge(
                  strings: const Strings(true),
                  todayEntry: const Entry(
                    date: '2026-10-01',
                    taken: true,
                    notes: '',
                  ),
                  onRecord: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Registrar hoje'), findsNothing);
      expect(find.text('Atualizar hoje'), findsNothing);
    });

    testWidgets('today nudge magnetically snaps across edges ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: Stack(
                children: [
                  TodayNudge(
                    strings: const Strings(false),
                    todayEntry: null,
                    onRecord: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final start = tester.getCenter(find.byIcon(Icons.add));
      expect(start.dx, greaterThan(200)); // default right edge

      await tester.drag(find.byIcon(Icons.add), const Offset(-220, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      final end = tester.getCenter(find.byIcon(Icons.add));
      // Plus stays on the pill’s top-right corner; after left snap the whole
      // control is near the left edge (plus center still inset from left).
      expect(end.dx, lessThan(start.dx - 80));
      final controlLeft =
          tester.getTopLeft(find.byKey(const ValueKey('today-nudge-control'))).dx;
      expect(controlLeft, lessThan(40));
    });
  }
}
