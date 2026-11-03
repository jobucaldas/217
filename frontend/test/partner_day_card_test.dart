import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/day_summary.dart';
import 'package:a217/src/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api(this.entries, {this.cycle = CycleInfo.empty})
      : super(AppConfig.fromEnvironment());
  final List<Entry> entries;
  final CycleInfo cycle;

  @override
  Future<CycleInfo> getCycle(String today) async => cycle;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;
}

const _partner = User(id: 'p', email: 'p@b.c', name: 'P', role: 'partner');
const _readOnly = ShareState(
  status: 'active',
  ownerName: 'Her',
  canEditCalendar: false,
);

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget _app(Widget home) => MaterialApp(
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: AppPalette.blue,
      ),
      home: home,
    );

CalendarScreen _calendar({
  required List<Entry> entries,
  User user = _partner,
  ShareState share = _readOnly,
  CycleInfo cycle = CycleInfo.empty,
}) =>
    CalendarScreen(
      api: _Api(entries, cycle: cycle),
      user: user,
      share: share,
      strings: const Strings(AppLanguage.en),
      onOpenSettings: () {},
    );

/// The sheet's button of [key], which is disabled when it has no handler.
bool _disabled(WidgetTester tester, Key key) =>
    tester
        .widget<IconButton>(find.descendant(
          of: find.byKey(key),
          matching: find.byType(IconButton),
        ))
        .onPressed ==
    null;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Another day of the visible month, not today.
  final other = DateTime(now.year, now.month, today.day == 15 ? 16 : 15);

  Finder cellOf(DateTime d) => find
      .descendant(
        of: find.byKey(ValueKey('${d.year}-${d.month}')),
        matching: find.text('${d.day}'),
      )
      .first;

  final sheet = find.byKey(const ValueKey('expandable-day-sheet'));

  /// Whether [key] is on screen and not clipped away by the resting sheet.
  bool shown(Key key) => find.byKey(key).hitTestable().evaluate().isNotEmpty;

  testWidgets('partner views a day as read-only chips, no controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: [
      Entry(
          date: _key(today),
          taken: true,
          notes: 'Felt fine today',
          heart: true,
          period: true),
    ])));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('update-day-button')), findsNothing);
    expect(find.text('View today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('partner-day-glance')), findsOneWidget);
    for (final id in ['pill', 'heart', 'period', 'note']) {
      expect(shown(ValueKey('day-chip-$id')), isTrue, reason: id);
    }
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-chip-pill')),
          matching: find.text('Taken')),
      findsOneWidget,
    );
    // Nothing that looks like the owner's controls.
    expect(find.byType(DayEditorSheet), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byKey(const ValueKey('day-heart-toggle')), findsNothing);
    expect(find.text('Missed'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // Same as the owner's sheet: no close button, a tap outside dismisses.
    expect(find.text('Close'), findsNothing);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('partner-day-glance')), findsNothing);
  });

  testWidgets('double tap on a day opens the read-only sheet for a partner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: [
      Entry(date: _key(other), taken: false, notes: 'Skipped'),
    ])));
    await tester.pumpAndSettle();

    await tester.tap(cellOf(other));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('partner-day-glance')), findsNothing);
    await tester.tap(cellOf(other));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('partner-day-glance')), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-chip-pill')),
          matching: find.text('Missed')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('partner can jump back to today', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jump-to-today-button')), findsNothing);
    await tester.tap(cellOf(other));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jump-to-today-button')), findsOneWidget);
    expect(find.text('View today'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('jump-to-today-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jump-to-today-button')), findsNothing);
    expect(find.text('View today'), findsOneWidget);
  });

  testWidgets('the sheet, open or not, closes when the share is revoked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = [
      Entry(date: _key(today), taken: true, notes: 'Private note'),
    ];
    await tester.pumpWidget(_app(_calendar(entries: entries)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    await tester.drag(sheet, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(shown(const ValueKey('day-more-note')), isTrue);

    await tester.pumpWidget(_app(_calendar(
      entries: entries,
      share: const ShareState(status: 'revoked', canEditCalendar: false),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('partner-day-glance')), findsNothing);
    expect(find.text('Private note'), findsNothing);
  });

  testWidgets('partner pulls the sheet up into cards, down to close',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longNote = 'A long note that the resting sheet does not spell out '
        'in full but the expanded one does.';
    await tester.pumpWidget(_app(_calendar(entries: [
      Entry(date: _key(today), taken: true, notes: longNote, heart: true),
    ])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    final restingTop = tester.getTopLeft(sheet).dy;
    expect(shown(const ValueKey('day-card-pill')), isFalse);
    expect(shown(const ValueKey('day-more-note')), isFalse);

    // Dragged by its body, not only the handle.
    await tester.drag(
        find.byKey(const ValueKey('day-chip-pill')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(restingTop));
    for (final key in [
      'day-card-pill',
      'day-card-heart',
      'day-more-note',
      'day-coming-up-title',
    ]) {
      expect(shown(ValueKey(key)), isTrue, reason: key);
    }
    expect(find.text(longNote), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);

    // Down once back to rest, once more to close.
    await tester.fling(sheet, const Offset(0, 300), 2000);
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(sheet).dy, moreOrLessEquals(restingTop, epsilon: 1));
    await tester.fling(sheet, const Offset(0, 300), 2000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('partner-day-glance')), findsNothing);
  });

  testWidgets('an empty day still pulls up, and the handle toggles it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    final top = tester.getTopLeft(sheet).dy;
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-chip-pill')),
          matching: find.text('Not logged yet')),
      findsOneWidget,
    );
    expect(shown(const ValueKey('day-coming-up-title')), isFalse);
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(top));
    expect(shown(const ValueKey('day-coming-up-title')), isTrue);

    // Collapsing does not close it.
    await tester.tap(find.byKey(const ValueKey('day-sheet-handle')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, moreOrLessEquals(top, epsilon: 1));
    expect(find.byKey(const ValueKey('partner-day-glance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-sheet-handle')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(top));
  });

  testWidgets('the owner pulls the same sheet up, and it follows the note',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(
      entries: [Entry(date: _key(today), taken: true, notes: 'First note')],
      user: const User(id: 'o', email: 'o@b.c', name: 'O'),
      share: const ShareState(status: 'none'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pumpAndSettle();

    final restingTop = tester.getTopLeft(sheet).dy;
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(restingTop));
    expect(shown(const ValueKey('day-more-note')), isTrue);
    // Still the editor: its controls work.
    expect(_disabled(tester, const ValueKey('day-heart-toggle')), isFalse);
  });

  testWidgets('the owner pulls up an empty day too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(
      entries: const [],
      user: const User(id: 'o', email: 'o@b.c', name: 'O'),
      share: const ShareState(status: 'none'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pumpAndSettle();

    final top = tester.getTopLeft(sheet).dy;
    expect(shown(const ValueKey('day-coming-up-title')), isFalse);
    // Dragged from the date, above the editor's controls.
    await tester.drag(
      find
          .descendant(
              of: find.byType(DayEditorSheet), matching: find.byType(Text))
          .first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(top));
    expect(shown(const ValueKey('day-coming-up-title')), isTrue);
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
  });

  const owner = User(id: 'o', email: 'o@b.c', name: 'O');
  const solo = ShareState(status: 'none');

  /// A finger pulling [dy] in small steps, as on a phone: the sheet's
  /// scroll view and the sheet itself both get to take part of it.
  Future<void> pull(WidgetTester tester, Finder from, double dy) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    const step = 20.0;
    for (var moved = 0.0; moved < dy.abs(); moved += step) {
      await gesture.moveBy(Offset(0, dy.sign * step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  double sheetScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
          find.descendant(of: sheet, matching: find.byType(Scrollable)))
      .position
      .pixels;

  testWidgets('the owner sheet turns into editable cards when pulled up',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(
      entries: [Entry(date: _key(today), taken: true, notes: 'Felt fine')],
      user: owner,
      share: solo,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pumpAndSettle();

    final restingTop = tester.getTopLeft(sheet).dy;
    expect(shown(const ValueKey('day-heart-toggle')), isTrue);
    expect(shown(const ValueKey('day-card-heart')), isFalse);
    // Editable: no lock or eye beside the date.
    expect(find.byKey(const ValueKey('day-sheet-locked')), findsNothing);
    expect(find.byKey(const ValueKey('day-sheet-view-only')), findsNothing);

    await pull(tester, sheet, -500);
    expect(tester.getTopLeft(sheet).dy, lessThan(restingTop));
    for (final key in [
      'day-card-heart',
      'day-card-period',
      'day-more-note',
      'day-coming-up-title',
    ]) {
      expect(shown(ValueKey(key)), isTrue, reason: key);
    }
    // The buttons gave way to the cards; Missed/Taken stays, pinned below.
    expect(shown(const ValueKey('day-heart-toggle')), isFalse);
    final status = find.byType(SegmentedButton<bool>);
    expect(status.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(status).dy,
      greaterThan(tester
          .getBottomLeft(find.byKey(const ValueKey('day-more-coming-up')))
          .dy),
    );

    // The cards still edit the day.
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-card-heart')),
          matching: find.text('Tap to log')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('day-card-heart')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-card-heart')),
          matching: find.text('Logged')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('day-more-note')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('pulling down from open stops at rest, the next pull closes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Longer than the open sheet: its content scrolls.
    final longNote = List.filled(40, 'Long day, wrote it all down.').join(' ');
    for (final asPartner in [false, true]) {
      await tester.pumpWidget(_app(_calendar(
        entries: [Entry(date: _key(today), taken: true, notes: longNote)],
        user: asPartner ? _partner : owner,
        share: asPartner ? _readOnly : solo,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          ValueKey(asPartner ? 'view-day-button' : 'update-day-button')));
      await tester.pumpAndSettle();
      final restingTop = tester.getTopLeft(sheet).dy;

      // Open, then on through the cards.
      await pull(tester, sheet, -600);
      final openTop = tester.getTopLeft(sheet).dy;
      expect(openTop, lessThan(restingTop));
      await pull(tester, sheet, -300);
      expect(sheetScroll(tester), greaterThan(0), reason: '$asPartner');

      // One long pull down: back through the cards, then down to rest only.
      await pull(tester, sheet, 1400);
      expect(find.byType(ExpandableDaySheet), findsOneWidget,
          reason: '$asPartner');
      expect(tester.getTopLeft(sheet).dy,
          moreOrLessEquals(restingTop, epsilon: 1));
      expect(sheetScroll(tester), 0);

      // From rest, a pull down closes it.
      await pull(tester, sheet, 400);
      expect(find.byType(ExpandableDaySheet), findsNothing,
          reason: '$asPartner');
    }
  });

  testWidgets('a tap outside closes the open sheet at once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final asPartner in [false, true]) {
      await tester.pumpWidget(_app(_calendar(
        entries: [Entry(date: _key(today), taken: true, notes: 'Note')],
        user: asPartner ? _partner : owner,
        share: asPartner ? _readOnly : solo,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          ValueKey(asPartner ? 'view-day-button' : 'update-day-button')));
      await tester.pumpAndSettle();
      await pull(tester, sheet, -500);
      expect(shown(const ValueKey('day-coming-up-title')), isTrue);

      await tester.tapAt(const Offset(195, 8));
      await tester.pumpAndSettle();
      expect(find.byType(ExpandableDaySheet), findsNothing,
          reason: '$asPartner');
    }
  });

  testWidgets('a future day opens read-only for the owner, with a lock',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(
      entries: const [],
      user: owner,
      share: solo,
    )));
    await tester.pumpAndSettle();
    final future = DateTime(today.year, today.month, today.day + 1);
    if (future.month != today.month) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    // A double tap opens it, as on any other day.
    await tester.tap(cellOf(future));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cellOf(future));
    await tester.pumpAndSettle();

    expect(find.byType(ExpandableDaySheet), findsOneWidget);
    expect(find.byKey(const ValueKey('day-sheet-locked')), findsOneWidget);
    expect(find.byTooltip('Future day: nothing to log yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-sheet-view-only')), findsNothing);
    expect(find.byType(DayEditorSheet), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byKey(const ValueKey('day-heart-toggle')), findsNothing);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('owner-day-glance')),
          matching: find.text('Not due yet')),
      findsOneWidget,
    );

    await pull(tester, sheet, -500);
    expect(shown(const ValueKey('day-card-pill')), isTrue);
    expect(shown(const ValueKey('day-coming-up-title')), isTrue);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byKey(const ValueKey('day-card-heart')), findsNothing);

    // The summary's button views the future day rather than updating it.
    await tester.tapAt(const Offset(206, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-day-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-sheet-locked')), findsOneWidget);
  });

  testWidgets('the partner sheet shows the view-only eye', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-sheet-view-only')), findsOneWidget);
    expect(find.byTooltip('Partner Mode: view only'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-sheet-locked')), findsNothing);
  });

  testWidgets('owner still gets the editor, not the read-only sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(
      entries: const [],
      user: const User(id: 'o', email: 'o@b.c', name: 'O'),
      share: const ShareState(status: 'none'),
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('view-day-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-day-glance')), findsNothing);
    expect(find.text('Close'), findsNothing);
    expect(_disabled(tester, const ValueKey('day-heart-toggle')), isFalse);
  });

  testWidgets('read-only sheet: chips turn into equal square tiles, once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cycle = CycleInfo(predictions: [
      CycleWindow(
        periodStart: today.add(const Duration(days: 6)),
        periodEnd: today.add(const Duration(days: 10)),
        pmsStart: today.subtract(const Duration(days: 1)),
        pmsEnd: today.add(const Duration(days: 5)),
      ),
    ]);
    await tester.pumpWidget(_app(_calendar(
      entries: [Entry(date: _key(today), taken: null, notes: 'A note')],
      cycle: cycle,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    // At rest: the chips and the "pull up" mark, nothing of the open state.
    const chips = ['day-chip-pill', 'day-chip-pms'];
    const tiles = ['day-card-pill', 'day-card-pms'];
    const coming = ['day-coming-pms', 'day-coming-period'];
    final more = find.byIcon(Icons.more_horiz);
    for (final k in chips) {
      expect(shown(ValueKey(k)), isTrue, reason: k);
    }
    expect(more.hitTestable(), findsOneWidget);
    for (final k in [...tiles, ...coming, 'day-more-note']) {
      expect(shown(ValueKey(k)), isFalse, reason: k);
    }

    await tester.drag(sheet, const Offset(0, -600));
    await tester.pumpAndSettle();
    // Open: each fact once, as a tile; the chips and the mark are gone.
    for (final k in chips) {
      expect(shown(ValueKey(k)), isFalse, reason: k);
    }
    expect(more.hitTestable(), findsNothing);
    for (final k in [...tiles, ...coming, 'day-coming-up-title']) {
      expect(shown(ValueKey(k)), isTrue, reason: k);
    }
    // Equal squares.
    final sizes = [
      for (final k in [...tiles, ...coming])
        tester.getSize(find.byKey(ValueKey(k))),
    ];
    for (final size in sizes) {
      expect(size.width, moreOrLessEquals(size.height, epsilon: 0.01));
      expect(size.width, moreOrLessEquals(sizes.first.width, epsilon: 0.01));
    }
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('day-coming-period')),
          matching: find.textContaining('~')),
      findsOneWidget,
    );
  });

  testWidgets('coming up without predictions is one muted line',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    await tester.drag(sheet, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(shown(const ValueKey('day-coming-up-title')), isTrue);
    expect(find.byKey(const ValueKey('day-coming-pms')), findsNothing);
    expect(find.byKey(const ValueKey('day-coming-period')), findsNothing);
    expect(find.text('No expected period or PMS for now.'), findsOneWidget);
  });
}
