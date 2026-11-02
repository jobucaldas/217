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

  testWidgets('partner views a day in a read-only card', (tester) async {
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

    expect(find.byKey(const ValueKey('day-info-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-card-status')), findsOneWidget);
    expect(find.text('Taken'), findsWidgets);
    expect(find.byKey(const ValueKey('day-card-heart')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-card-period')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-card-note')), findsOneWidget);
    expect(find.text('Felt fine today'), findsWidgets);
    // Read-only: nothing to edit, only a close action.
    expect(find.byType(DayEditorSheet), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byKey(const ValueKey('day-card-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-card-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-info-card')), findsNothing);
  });

  testWidgets('double tap on a day opens the card for a partner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: [
      Entry(date: _key(other), taken: false, notes: 'Skipped'),
    ])));
    await tester.pumpAndSettle();

    await tester.tap(cellOf(other));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('day-info-card')), findsNothing);
    await tester.tap(cellOf(other));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('day-info-card')), findsOneWidget);
    expect(find.text('Missed'), findsWidgets);
    expect(find.byType(DayEditorSheet), findsNothing);
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

  testWidgets('the card closes when the share is revoked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_calendar(entries: const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-info-card')), findsOneWidget);

    await tester.pumpWidget(_app(_calendar(
      entries: const [],
      share: const ShareState(status: 'revoked', canEditCalendar: false),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-info-card')), findsNothing);
  });

  testWidgets('owner still gets the editor, not the card', (tester) async {
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
    expect(find.byKey(const ValueKey('day-info-card')), findsNothing);
  });
}
