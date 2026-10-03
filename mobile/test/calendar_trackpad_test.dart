import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _FakeCalendarApi extends ApiClient {
  _FakeCalendarApi() : super(AppConfig.fromEnvironment());

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];
}

String _label(int monthDelta) {
  final now = DateTime.now();
  return DateFormat.yMMMM('en_US')
      .format(DateTime(now.year, now.month + monthDelta));
}

Future<void> _pumpCalendar(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.azure,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CalendarScreen(
          api: _FakeCalendarApi(),
          user: const User(
            id: 'u1',
            email: 'shot@example.invalid',
            name: 'Shot',
          ),
          strings: const Strings(AppLanguage.en),
          onOpenSettings: () {},
          palette: AppPalette.azure,
        ),
      ),
    ),
  );
  // Chip settle bounce (~860ms) + load.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();
  expect(find.text(_label(0)), findsOneWidget);
}

Offset _carouselCenter(WidgetTester tester) =>
    tester.getCenter(find.byKey(const ValueKey('month-carousel')));

/// Wheel / web-touchpad scroll: a burst of scroll signals, then idle.
Future<void> _scroll(
  WidgetTester tester,
  List<Offset> deltas, {
  PointerDeviceKind kind = PointerDeviceKind.trackpad,
}) async {
  final pointer = TestPointer(1, kind);
  pointer.hover(_carouselCenter(tester));
  for (final d in deltas) {
    await tester.sendEventToBinding(pointer.scroll(d));
    await tester.pump(const Duration(milliseconds: 16));
  }
  // Past the idle gap that ends a scroll gesture, then settle the snap.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Native two-finger trackpad pan (PointerPanZoom sequence).
Future<void> _panZoom(WidgetTester tester, Offset total, {int steps = 10}) async {
  final pointer = TestPointer(2, PointerDeviceKind.trackpad);
  final at = _carouselCenter(tester);
  var t = Duration.zero;
  await tester.sendEventToBinding(pointer.panZoomStart(at, timeStamp: t));
  for (var i = 1; i <= steps; i++) {
    t += const Duration(milliseconds: 16);
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(at, pan: total * (i / steps), timeStamp: t),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.sendEventToBinding(
    pointer.panZoomEnd(timeStamp: t + const Duration(milliseconds: 16)),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('touchpad scroll signals', () {
    testWidgets('two-finger swipe left (scroll right) → next month',
        (tester) async {
      await _pumpCalendar(tester);
      await _scroll(tester, const [Offset(30, 0), Offset(40, 2), Offset(50, 0)]);
      expect(find.text(_label(1)), findsOneWidget);
    });

    testWidgets('two-finger swipe right (scroll left) → previous month',
        (tester) async {
      await _pumpCalendar(tester);
      await _scroll(tester, const [Offset(-30, 0), Offset(-40, 0), Offset(-50, 0)]);
      expect(find.text(_label(-1)), findsOneWidget);
    });

    testWidgets('vertical scroll pages months (down = next, up = previous)',
        (tester) async {
      await _pumpCalendar(tester);
      await _scroll(tester, const [Offset(0, 100)],
          kind: PointerDeviceKind.mouse);
      expect(find.text(_label(1)), findsOneWidget);
      await _scroll(tester, const [Offset(0, -100)],
          kind: PointerDeviceKind.mouse);
      await _scroll(tester, const [Offset(0, -100)],
          kind: PointerDeviceKind.mouse);
      expect(find.text(_label(-1)), findsOneWidget);
    });

    testWidgets('one wheel notch is enough on wide layouts', (tester) async {
      await _pumpCalendar(tester, size: const Size(1440, 900));
      await _scroll(tester, const [Offset(0, 100)],
          kind: PointerDeviceKind.mouse);
      expect(find.text(_label(1)), findsOneWidget);
    });

    testWidgets('momentum tail of one swipe moves exactly one month',
        (tester) async {
      await _pumpCalendar(tester);
      await _scroll(tester, [
        for (var i = 0; i < 60; i++) Offset(80.0 - i, 0),
      ]);
      expect(find.text(_label(1)), findsOneWidget);
    });

    testWidgets('tiny scroll springs back to the same month', (tester) async {
      await _pumpCalendar(tester);
      await _scroll(tester, const [Offset(8, 0), Offset(6, 0)]);
      expect(find.text(_label(0)), findsOneWidget);
    });
  });

  group('native trackpad pan/zoom', () {
    testWidgets('horizontal two-finger pan left → next month', (tester) async {
      await _pumpCalendar(tester);
      await _panZoom(tester, const Offset(-200, 0));
      expect(find.text(_label(1)), findsOneWidget);
    });

    testWidgets('vertical two-finger pan down → previous month',
        (tester) async {
      await _pumpCalendar(tester);
      await _panZoom(tester, const Offset(0, 200));
      expect(find.text(_label(-1)), findsOneWidget);
    });

    testWidgets('short slow pan snaps back', (tester) async {
      await _pumpCalendar(tester);
      await _panZoom(tester, const Offset(-20, 0), steps: 40);
      expect(find.text(_label(0)), findsOneWidget);
    });
  });

  testWidgets('touch swipe still changes month', (tester) async {
    await _pumpCalendar(tester);
    await tester.fling(
      find.byKey(const ValueKey('month-carousel')),
      const Offset(-420, 0),
      1400,
    );
    await tester.pumpAndSettle();
    expect(find.text(_label(1)), findsOneWidget);
  });
}
