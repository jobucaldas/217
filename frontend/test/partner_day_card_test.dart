import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api(this.entries) : super(AppConfig.fromEnvironment());
  final List<Entry> entries;

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
}) =>
    CalendarScreen(
      api: _Api(entries),
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
  bool shown(Key key) =>
      find.byKey(key).hitTestable().evaluate().isNotEmpty;

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
      'day-more-coming-up',
    ]) {
      expect(shown(ValueKey(key)), isTrue, reason: key);
    }
    expect(find.text(longNote), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);

    // Down once back to rest, once more to close.
    await tester.fling(sheet, const Offset(0, 300), 2000);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, moreOrLessEquals(restingTop, epsilon: 1));
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
    expect(shown(const ValueKey('day-more-coming-up')), isFalse);
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(top));
    expect(shown(const ValueKey('day-more-coming-up')), isTrue);

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
    expect(shown(const ValueKey('day-more-coming-up')), isFalse);
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
    expect(shown(const ValueKey('day-more-coming-up')), isTrue);
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
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
}
