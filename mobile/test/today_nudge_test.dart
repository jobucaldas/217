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
        'today nudge hugs text with outer-corner plus when unrecorded ($brightness)',
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

      final size =
          tester.getSize(find.byKey(const ValueKey('today-nudge-control')));
      expect(size.height, TodayNudge.height);
      // Hugs text — not a stretched wide bar.
      expect(size.width, lessThan(240));
      expect(size.width, greaterThan(120));

      // Default right edge → plus on top-right corner.
      final plusCenter = tester.getCenter(find.byIcon(Icons.add));
      final controlTopLeft =
          tester.getTopLeft(find.byKey(const ValueKey('today-nudge-control')));
      expect(
        plusCenter.dy,
        lessThan(controlTopLeft.dy + TodayNudge.pillHeight / 2),
      );
      expect(
        plusCenter.dx,
        greaterThan(controlTopLeft.dx + size.width * 0.55),
      );
    });

    testWidgets('today nudge English label is narrower than Portuguese ($brightness)',
        (tester) async {
      Future<double> widthFor(bool pt) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(brightness: brightness),
            home: Scaffold(
              body: Stack(
                children: [
                  TodayNudge(
                    strings: Strings(pt),
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
        return tester
            .getSize(find.byKey(const ValueKey('today-nudge-control')))
            .width;
      }

      final en = await widthFor(false);
      expect(find.text('Update today'), findsOneWidget);
      final pt = await widthFor(true);
      expect(find.text('Atualizar hoje'), findsOneWidget);
      expect(en, lessThan(pt));
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

    testWidgets(
        'today nudge still visible for Em aberto note/heart only ($brightness)',
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
                    taken: null,
                    notes: 'note only',
                    heart: true,
                  ),
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
    });

    testWidgets(
        'today nudge snaps left and flips plus to top-left ($brightness)',
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
      expect(start.dx, greaterThan(200)); // default right / top-right plus

      await tester.drag(find.byIcon(Icons.add), const Offset(-220, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      final control = find.byKey(const ValueKey('today-nudge-control'));
      final controlLeft = tester.getTopLeft(control).dx;
      final controlRight = tester.getTopRight(control).dx;
      final plus = tester.getCenter(find.byIcon(Icons.add));
      expect(controlLeft, lessThan(40));
      // Outer top corner on the left edge → plus nearer left than right.
      expect(plus.dx - controlLeft, lessThan(controlRight - plus.dx));
      expect(plus.dy, lessThan(tester.getCenter(control).dy));
    });
  }
}
