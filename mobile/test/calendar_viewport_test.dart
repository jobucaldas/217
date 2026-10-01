import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _FakeCalendarApi extends ApiClient {
  _FakeCalendarApi([this.entries = const []])
      : super(AppConfig.fromEnvironment());

  final List<Entry> entries;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;

  @override
  Future<Entry> upsertEntry(
    String date, {
    required bool taken,
    String notes = '',
    bool heart = false,
  }) async =>
      Entry(date: date, taken: taken, notes: notes, heart: heart);

  @override
  Future<void> deleteEntry(String date) async {}
}

/// Holds subsequent loads so tests can assert geometry mid-fetch.
class _GatedCalendarApi extends _FakeCalendarApi {
  _GatedCalendarApi() : super();

  int _calls = 0;
  Completer<void>? _gate;

  /// After the initial triple prefetch, further listEntries wait on [release].
  void armHang() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    _calls++;
    // First paint loads current + prev + next (3 calls).
    if (_calls > 3 && _gate != null && !_gate!.isCompleted) {
      await _gate!.future;
    }
    return entries;
  }
}

/// Representative monitor / window sizes where the month grid used to crop.
const _viewports = <(String, Size)>[
  ('phone', Size(390, 844)),
  ('phone_short', Size(360, 640)),
  ('laptop_short', Size(1280, 700)),
  ('ultrawide_short', Size(1920, 720)),
  ('tablet', Size(820, 1180)),
  ('desktop', Size(1440, 900)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final (name, size) in _viewports) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'calendar fits full month on $name / ${brightness.name}',
        (tester) async {
          final errors = <FlutterErrorDetails>[];
          final old = FlutterError.onError;
          FlutterError.onError = (details) {
            errors.add(details);
            old?.call(details);
          };
          addTearDown(() => FlutterError.onError = old);

          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              theme: buildApp217Theme(
                brightness: brightness,
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
                  strings: Strings(false),
                  onOpenSettings: () {},
                  palette: AppPalette.azure,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('217'), findsOneWidget);
          // Last day of a 31-day month must be on screen (no crop).
          final now = DateTime.now();
          final lastDay =
              DateTime(now.year, now.month + 1, 0).day.toString();
          expect(find.text(lastDay), findsWidgets);

          final overflow = errors.where(
            (e) =>
                e.toString().contains('overflowed') ||
                e.toString().contains('RenderFlex'),
          );
          expect(
            overflow,
            isEmpty,
            reason: 'overflow on $name/${brightness.name}: $overflow',
          );
        },
      );
    }
  }

  test('pinned dark scaffold is #121212 for every accent', () {
    for (final p in AppPalette.values) {
      expect(
        scaffoldBackgroundFor(Brightness.dark, palette: p),
        const Color(0xFF121212),
      );
      expect(
        buildApp217ColorScheme(Brightness.dark, palette: p).surface,
        const Color(0xFF1C1C1C),
      );
    }
  });

  testWidgets(
    'record-today chip is a Positioned overlay (grid keeps 12px inset)',
    (tester) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const gridPadding = EdgeInsets.fromLTRB(12, 4, 12, 12);
      final reservedForFab = find.byWidgetPredicate(
        (w) =>
            w is Padding &&
            w.padding == const EdgeInsets.fromLTRB(12, 4, 12, 72),
      );
      final overlayInset = find.byWidgetPredicate(
        (w) => w is Padding && w.padding == gridPadding,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: Brightness.light,
            palette: AppPalette.azure,
          ),
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: CalendarScreen(
              api: _FakeCalendarApi(),
              user: const User(
                id: 'u1',
                email: 'shot@example.invalid',
                name: 'Shot',
              ),
              strings: const Strings(false),
              onOpenSettings: () {},
              palette: AppPalette.azure,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Update today'), findsOneWidget);
      expect(find.byType(Positioned), findsWidgets);
      // Carousel keeps three month pages; each uses the 12px bottom inset.
      expect(overlayInset, findsNWidgets(3));
      expect(
        reservedForFab,
        findsNothing,
        reason: 'chip must not inflate month-grid bottomInset',
      );
    },
  );

  testWidgets('horizontal carousel swipe changes month with snap', (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: _FakeCalendarApi(),
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(false),
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

    final now = DateTime.now();
    final labelBefore = find.textContaining('${now.year}');
    expect(labelBefore, findsWidgets);

    // Carousel uses Transform.translate pages, not AnimatedSwitcher.
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(ClipRect), findsWidgets);

    await tester.fling(
      find.byType(ClipRect).first,
      const Offset(-420, 0),
      1400,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    final next = DateTime(now.year, now.month + 1);
    expect(find.textContaining('${next.year}'), findsWidgets);
  });

  testWidgets('month change keeps carousel height (no loading reflow)',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _GatedCalendarApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: api,
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(false),
            onOpenSettings: () {},
            palette: AppPalette.azure,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    final carousel = find.byKey(const ValueKey('month-carousel'));
    expect(carousel, findsOneWidget);
    final sizeBefore = tester.getSize(carousel);

    api.armHang();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // Mid-fetch: no progress chrome, carousel height unchanged.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getSize(carousel), sizeBefore);

    api.release();
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getSize(carousel), sizeBefore);
  });
}
