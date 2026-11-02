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

  testWidgets('partner views a day in the owner sheet, read-only',
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
    expect(find.text('See today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    expect(find.byType(DayEditorSheet), findsOneWidget);
    expect(find.text('Taken'), findsWidgets);
    // Every control is shown but disabled.
    expect(_disabled(tester, const ValueKey('day-heart-toggle')), isTrue);
    expect(_disabled(tester, const ValueKey('day-period-toggle')), isTrue);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );
    expect(find.byType(TextField), findsNothing);

    // The note opens read-only, in its card.
    await tester.tap(find.byIcon(Icons.sticky_note_2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsOneWidget);
    expect(find.text('Felt fine today'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsNothing);

    // Same as the owner's sheet: no close button, a tap outside dismisses.
    expect(find.text('Close'), findsNothing);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsNothing);
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
    expect(find.byType(DayEditorSheet), findsNothing);
    await tester.tap(cellOf(other));
    await tester.pumpAndSettle();

    expect(find.byType(DayEditorSheet), findsOneWidget);
    expect(find.text('Missed'), findsWidgets);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );
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
    expect(find.text('See today'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('jump-to-today-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jump-to-today-button')), findsNothing);
    expect(find.text('See today'), findsOneWidget);
  });

  testWidgets('the sheet closes when the share is revoked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);

    await tester.pumpWidget(_app(_calendar(
      entries: const [],
      share: const ShareState(status: 'revoked', canEditCalendar: false),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsNothing);
  });

  testWidgets('an open note card closes too when the share is revoked',
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
    await tester.tap(find.byIcon(Icons.sticky_note_2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsOneWidget);

    await tester.pumpWidget(_app(_calendar(
      entries: entries,
      share: const ShareState(status: 'revoked', canEditCalendar: false),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsNothing);
    expect(find.text('Private note'), findsNothing);
    expect(find.byType(DayEditorSheet), findsNothing);
  });


  testWidgets('partner pulls the sheet up for more, down to close',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longNote = 'A long note that the resting sheet does not spell out '
        'in full but the expanded one does.';
    await tester.pumpWidget(_app(_calendar(entries: [
      Entry(date: _key(today), taken: true, notes: longNote),
    ])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('expandable-day-sheet'));
    final restingTop = tester.getTopLeft(sheet).dy;
    expect(find.byKey(const ValueKey('day-more-note')), findsOneWidget);
    expect(find.byType(DayEditorSheet), findsOneWidget);

    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(restingTop));
    expect(find.text(longNote), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );

    await tester.fling(sheet, const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsNothing);
  });

  testWidgets('a day with nothing more keeps the owner-sized sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('expandable-day-sheet'));
    final top = tester.getTopLeft(sheet).dy;
    expect(find.byKey(const ValueKey('day-more-note')), findsNothing);
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, top);
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

    final sheet = find.byKey(const ValueKey('expandable-day-sheet'));
    final restingTop = tester.getTopLeft(sheet).dy;
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, lessThan(restingTop));
    expect(find.text('First note'), findsOneWidget);
    // Still the editor: its controls work.
    expect(_disabled(tester, const ValueKey('day-heart-toggle')), isFalse);
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
    expect(find.text('Close'), findsNothing);
    expect(_disabled(tester, const ValueKey('day-heart-toggle')), isFalse);
  });
}
