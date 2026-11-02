import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/notifications/partner_alert_sync_queue.dart';
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
    bool? taken,
    String notes = '',
    bool heart = false,
    bool period = false,
  }) async =>
      Entry(
        date: date,
        taken: taken,
        notes: notes,
        heart: heart,
        period: period,
      );

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

/// Counts month reads.
class _CountingCalendarApi extends _FakeCalendarApi {
  int calls = 0;

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    calls++;
    return entries;
  }
}

class _CalendarOwnerConsentApi extends _FakeCalendarApi {
  _CalendarOwnerConsentApi(super.entries);

  int _calls = 0;

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    _calls++;
    if (_calls > 3) {
      throw ApiException(
        'list entries',
        http.Response('{"error":"calendar owner consent required"}', 403),
      );
    }
    return entries;
  }
}

class _RacingCalendarApi extends _FakeCalendarApi {
  _RacingCalendarApi(super.entries);

  final firstLoadGate = Completer<void>();
  int _calls = 0;

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    _calls++;
    if (_calls <= 3) {
      await firstLoadGate.future;
      return entries;
    }
    throw ApiException(
      'list entries',
      http.Response('{"error":"calendar owner consent required"}', 403),
    );
  }
}

class _CycleOwnerConsentApi extends _FakeCalendarApi {
  _CycleOwnerConsentApi(super.entries);

  @override
  Future<CycleInfo> getCycle(String today) async => throw ApiException(
        'get cycle',
        http.Response('{"error":"calendar owner consent required"}', 403),
      );
}

class _GatedPartnerCycleApi extends _FakeCalendarApi {
  final cycleGate = Completer<void>();

  @override
  Future<CycleInfo> getCycle(String today) async {
    await cycleGate.future;
    return CycleInfo.empty;
  }

  @override
  Future<PartnerAlertPreference> getPartnerAlerts() async =>
      const PartnerAlertPreference(pillEnabled: true);
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

  testWidgets(
      'delayed partner cycle cannot schedule after session invalidation',
      (tester) async {
    final api = _GatedPartnerCycleApi();
    final scheduled = <List<PlannedAlert>>[];
    var sessionGeneration = 1;
    final queue = PartnerAlertSyncQueue(
      scheduler: (alerts) async {
        scheduled.add(alerts);
        return LocalReminderSyncStatus.scheduled;
      },
      canceller: () async {},
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.blue,
      ),
      home: CalendarScreen(
        api: api,
        user: const User(
          id: 'partner',
          email: 'p@example.invalid',
          name: 'P',
          role: 'partner',
        ),
        strings: const Strings(AppLanguage.en),
        onOpenSettings: () {},
        share: const ShareState(status: 'active'),
        partnerAlertSyncQueue: queue,
        sessionGeneration: () => sessionGeneration,
        isSessionCurrent: (generation, _) => generation == sessionGeneration,
      ),
    ));
    await tester.pump();

    sessionGeneration++;
    await queue.cancel();
    api.cycleGate.complete();
    await tester.pumpAndSettle();

    expect(scheduled, isEmpty);
  });

  testWidgets('owner consent block clears previously visible calendar data',
      (tester) async {
    final today = DateTime.now();
    final entryDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final periodMarker = ValueKey('period-${today.month}-${today.day}');
    final api = _CalendarOwnerConsentApi([
      Entry(
        date: entryDate,
        taken: true,
        notes: 'cached private note',
        heart: true,
        period: true,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.blue,
      ),
      home: CalendarScreen(
        api: api,
        user: const User(
            id: 'partner',
            email: 'p@example.invalid',
            name: 'P',
            role: 'partner'),
        strings: const Strings(AppLanguage.en),
        onOpenSettings: () {},
        share: const ShareState(status: 'active'),
        palette: AppPalette.blue,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(periodMarker), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(periodMarker), findsNothing);
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
  });

  testWidgets('owner consent block invalidates an older pending calendar load',
      (tester) async {
    final today = DateTime.now();
    final entryDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final periodMarker = ValueKey('period-${today.month}-${today.day}');
    final api = _RacingCalendarApi([
      Entry(date: entryDate, taken: true, notes: '', period: true),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.blue,
      ),
      home: CalendarScreen(
        api: api,
        user: const User(
            id: 'partner',
            email: 'p@example.invalid',
            name: 'P',
            role: 'partner'),
        strings: const Strings(AppLanguage.en),
        onOpenSettings: () {},
        share: const ShareState(status: 'active'),
        palette: AppPalette.blue,
      ),
    ));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);

    api.firstLoadGate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(periodMarker), findsNothing);
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
  });

  testWidgets('owner consent block from cycle request clears the calendar',
      (tester) async {
    final today = DateTime.now();
    final entryDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final periodMarker = ValueKey('period-${today.month}-${today.day}');
    final scheduled = <List<PlannedAlert>>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.blue,
      ),
      home: CalendarScreen(
        api: _CycleOwnerConsentApi([
          Entry(date: entryDate, taken: true, notes: '', period: true),
        ]),
        user: const User(
            id: 'partner',
            email: 'p@example.invalid',
            name: 'P',
            role: 'partner'),
        strings: const Strings(AppLanguage.en),
        onOpenSettings: () {},
        share: const ShareState(status: 'active'),
        partnerAlertScheduler: (alerts) async {
          scheduled.add(alerts);
          return LocalReminderSyncStatus.cancelled;
        },
        palette: AppPalette.blue,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(periodMarker), findsNothing);
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
    expect(scheduled, hasLength(1));
    expect(scheduled.single, isEmpty);
    expect(
      find.text(
        'The calendar owner must agree to the current privacy notice before you can view their calendar.',
      ),
      findsOneWidget,
    );
  });

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
                palette: AppPalette.blue,
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
                  strings: Strings(AppLanguage.en),
                  onOpenSettings: () {},
                  palette: AppPalette.blue,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('217'), findsOneWidget);
          // Last day of a 31-day month must be on screen (no crop).
          final now = DateTime.now();
          final lastDay = DateTime(now.year, now.month + 1, 0).day.toString();
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

  for (final (name, size, capped) in <(String, Size, bool)>[
    ('portrait phone', const Size(390, 844), true),
    ('short landscape', const Size(900, 400), false),
  ]) {
    testWidgets('day cell height on $name', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: Brightness.light,
            palette: AppPalette.blue,
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
              palette: AppPalette.blue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Days 10 and 17 share a column one week apart in any month. Grid
      // width is the screen minus the 12px side padding, split in 7 columns.
      final tenth = tester.getCenter(find.text('10').last);
      final seventeenth = tester.getCenter(find.text('17').last);
      final cellWidth = (size.width - 24) / 7;
      final cellHeight = seventeenth.dy - tenth.dy;
      if (capped) {
        expect(cellHeight, closeTo(cellWidth * 1.15, 0.5));
      } else {
        expect(cellHeight, lessThan(cellWidth * 1.15));
      }
    });
  }

  testWidgets(
    'update-today button sits under the grid and opens today; tags and note show',
    (tester) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day)
          .toIso8601String()
          .substring(0, 10);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: Brightness.light,
            palette: AppPalette.blue,
          ),
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: CalendarScreen(
              api: _FakeCalendarApi([
                Entry(
                    date: today, taken: true, notes: 'Felt fine', heart: true),
              ]),
              user: const User(
                id: 'u1',
                email: 'shot@example.invalid',
                name: 'Shot',
              ),
              strings: const Strings(AppLanguage.en),
              onOpenSettings: () {},
              palette: AppPalette.blue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('update-day-button'));
      expect(find.text('Update today'), findsOneWidget);
      expect(find.byKey(const ValueKey('day-tag-heart')), findsOneWidget);
      // The note is drawn inline, so its tag is left out.
      expect(find.byKey(const ValueKey('day-tag-note')), findsNothing);
      expect(find.text('Felt fine'), findsOneWidget);
      final carousel = find.byKey(const ValueKey('month-carousel'));
      expect(
        tester.getTopLeft(button).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(carousel).dy),
      );
      // Month pages keep their 12px inset.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Padding &&
              w.padding == const EdgeInsets.fromLTRB(12, 4, 12, 12),
        ),
        findsNWidgets(3),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorSheet), findsOneWidget);
    },
  );

  testWidgets('swipe with a note showing changes month; days stay tappable',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .toIso8601String()
        .substring(0, 10);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: _FakeCalendarApi([
              Entry(date: today, taken: true, notes: 'Felt fine'),
            ]),
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Felt fine'), findsOneWidget);

    // Finger drag (not fling) so the gesture spans several frames.
    final carousel = find.byKey(const ValueKey('month-carousel'));
    final gesture = await tester.startGesture(tester.getCenter(carousel));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final prev = DateTime(now.year, now.month - 1);
    final grid = find.byKey(ValueKey('${prev.year}-${prev.month}'));
    expect(
      find.text(DateFormat.yMMMM('en_US').format(prev)),
      findsOneWidget,
    );
    expect(find.text('Felt fine'), findsOneWidget);

    await tester.tap(find.descendant(of: grid, matching: find.text('15')));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);
  });

  testWidgets('header month flips at 60% of the drag; note stays visible',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .toIso8601String()
        .substring(0, 10);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: _FakeCalendarApi([
              Entry(date: today, taken: true, notes: 'Felt fine'),
            ]),
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final current = find.text(DateFormat.yMMMM('en_US').format(now));
    final prev = DateTime(now.year, now.month - 1);
    final previous = find.text(DateFormat.yMMMM('en_US').format(prev));
    expect(find.text('Felt fine'), findsOneWidget);

    // The note lives in the bottom bar, above the tags and button, outside
    // the month carousel, and never moves while swiping.
    final note = find.byKey(const ValueKey('day-note'));
    final noteTop = tester.getTopLeft(note);
    final carousel = find.byKey(const ValueKey('month-carousel'));
    expect(
      tester.getTopLeft(note).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(carousel).dy),
    );
    expect(
      tester.getBottomLeft(note).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('day-tag-status'))).dy,
      ),
    );
    // Shown inline, the note has no tag of its own.
    expect(find.byKey(const ValueKey('day-tag-note')), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(carousel));
    // Slop first, then 40% of the 390px width.
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(136, 0));
    await tester.pump();
    expect(current, findsOneWidget);
    expect(find.text('Felt fine'), findsOneWidget);

    // 70% across: the header already names the previous month.
    await gesture.moveBy(const Offset(117, 0));
    await tester.pump();
    expect(previous, findsOneWidget);
    expect(current, findsNothing);
    expect(find.text('Felt fine'), findsOneWidget);
    expect(tester.getTopLeft(note), noteTop);

    // Dragged back under 60%: the label returns.
    await gesture.moveBy(const Offset(-117, 0));
    await tester.pump();
    expect(current, findsOneWidget);
    expect(find.text('Felt fine'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Felt fine'), findsOneWidget);
    expect(tester.getTopLeft(note), noteTop);
  });

  testWidgets('fast swipes each count, and the server is asked once',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _CountingCalendarApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
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
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final carousel = find.byKey(const ValueKey('month-carousel'));
    final before = api.calls;

    // Four swipes, each grabbing the grid while the last is still sliding.
    for (var i = 0; i < 4; i++) {
      final g = await tester.startGesture(tester.getCenter(carousel));
      await g.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final target = DateTime(now.year, now.month - 4);
    expect(
      find.text(DateFormat.yMMMM('en_US').format(target)),
      findsOneWidget,
    );
    // The first swipe loads at once; the burst after it waits to calm down
    // and then reads one set of three months.
    expect(api.calls - before, lessThanOrEqualTo(9));
  });

  testWidgets('short screens show the note as a tag that opens a card',
      (tester) async {
    const size = Size(900, 400);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .toIso8601String()
        .substring(0, 10);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: _FakeCalendarApi([
              Entry(date: today, taken: true, notes: 'Long note. ' * 60),
            ]),
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Short screen: no inline note, a tag opens it in a card.
    expect(find.byKey(const ValueKey('day-note')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('day-tag-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsOneWidget);
    expect(find.textContaining('Long note.'), findsOneWidget);
  });

  testWidgets('tapping a long inline note opens the whole note',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .toIso8601String()
        .substring(0, 10);
    final note = 'Long note. ' * 60;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: CalendarScreen(
            api: _FakeCalendarApi([
              Entry(date: today, taken: true, notes: note),
            ]),
            user: const User(
              id: 'u1',
              email: 'shot@example.invalid',
              name: 'Shot',
            ),
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Inline, capped to three lines, and no separate note tag.
    expect(find.byKey(const ValueKey('day-tag-note')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('day-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsOneWidget);
    expect(find.text(note.trim()), findsNWidgets(2));
  });

  testWidgets('horizontal carousel swipe changes month with snap',
      (tester) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
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
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
          ),
        ),
      ),
    );
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
          palette: AppPalette.blue,
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
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
            palette: AppPalette.blue,
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

  for (final (name, size, inlineNote, header) in [
    ('tall', const Size(390, 844), true, true),
    ('medium', const Size(390, 650), false, true),
    ('short', const Size(390, 560), false, false),
  ]) {
    testWidgets('$name screen: note inline=$inlineNote, header=$header',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day)
          .toIso8601String()
          .substring(0, 10);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: Brightness.light,
            palette: AppPalette.blue,
          ),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: CalendarScreen(
              api: _FakeCalendarApi([
                Entry(date: today, taken: true, notes: 'Felt fine'),
              ]),
              user: const User(id: 'u1', email: 'a@example.invalid', name: 'A'),
              strings: const Strings(AppLanguage.en),
              onOpenSettings: () {},
              palette: AppPalette.blue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('day-note')),
        inlineNote ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-header')),
        header ? findsOneWidget : findsNothing,
      );
      // The status stays reachable in the bottom bar.
      expect(find.byKey(const ValueKey('day-tag-status')), findsOneWidget);
    });
  }
}
