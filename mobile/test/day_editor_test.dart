import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

/// Lightweight fake covering clear-mark API path used by the day editor.
class _FakeApi extends ApiClient {
  _FakeApi() : super(AppConfig.fromEnvironment());

  final Map<String, Entry> store = {};

  @override
  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
  }) async {
    final e = Entry(date: date, taken: taken, notes: notes, heart: heart);
    store[date] = e;
    return e;
  }

  @override
  Future<void> deleteEntry(String date) async {
    store.remove(date);
  }
}

void main() {
  test('deleteEntry clears a stored day mark', () async {
    final api = _FakeApi();
    await api.upsertEntry('2026-10-01', taken: true, notes: 'x', heart: true);
    expect(api.store.containsKey('2026-10-01'), isTrue);
    expect(api.store['2026-10-01']!.heart, isTrue);
    await api.deleteEntry('2026-10-01');
    expect(api.store.containsKey('2026-10-01'), isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'note dialog text readable + heart toggle ($brightness)',
      (tester) async {
        final scheme = buildApp217ColorScheme(
          brightness,
          palette: AppPalette.azure,
        );
        final strings = const Strings(false);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.azure,
            ),
            home: Scaffold(
              body: DayEditorSheet(
                strings: strings,
                date: '2026-10-01',
                initialTaken: null,
                initialNotes: '',
                initialHeart: false,
                hadEntry: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Add note'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('note-heart-toggle')), findsOneWidget);
        // Cancel removed — outside/barrier dismisses.
        expect(find.text('Cancel'), findsNothing);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.style?.color, scheme.onSurface);
        final contrast = (field.style!.color!.computeLuminance() -
                scheme.surface.computeLuminance())
            .abs();
        expect(contrast, greaterThan(0.25));

        await tester.enterText(find.byType(TextField), 'hello note');
        await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.favorite), findsWidgets);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        // Embedded sheet (no modal): state updates in place; icons show.
        expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        final sheetHeart =
            tester.widget<Icon>(find.byIcon(Icons.favorite).first);
        expect(sheetHeart.color, scheme.primary);
        expect(sheetHeart.color, isNot(const Color(0xFFE11D48)));
        expect(find.text('Taken'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Save'), findsNothing);
      },
    );
  }

  testWidgets('Em aberto: note Done alone persists without Taken/Missed',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: null,
                    initialNotes: '',
                    initialHeart: false,
                    hadEntry: false,
                    onCommit: (result) => committed = result,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'open day note');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.clear, isFalse);
    expect(committed?.taken, isNull);
    expect(committed?.notes, 'open day note');
    expect(committed?.heart, isFalse);
    expect(find.text('Taken'), findsNothing);
  });

  testWidgets('Em aberto: heart alone persists without Taken/Missed',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: null,
                    initialNotes: '',
                    initialHeart: false,
                    hadEntry: false,
                    onCommit: (result) => committed = result,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.clear, isFalse);
    expect(committed?.taken, isNull);
    expect(committed?.notes, '');
    expect(committed?.heart, isTrue);
    expect(find.text('Taken'), findsNothing);
  });

  testWidgets(
      'Em aberto: reopen after Done shows persisted note + heart',
      (tester) async {
    final api = _FakeApi();
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: null,
                    initialNotes: '',
                    initialHeart: false,
                    hadEntry: false,
                    onCommit: (result) async {
                      committed = result;
                      if (!result.clear) {
                        await api.upsertEntry(
                          '2026-10-01',
                          taken: result.taken,
                          notes: result.notes,
                          heart: result.heart,
                        );
                      }
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keep me');
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.taken, isNull);
    expect(api.store['2026-10-01']?.notes, 'keep me');
    expect(api.store['2026-10-01']?.heart, isTrue);
    expect(api.store['2026-10-01']?.taken, isNull);

    // Reopen with persisted state — Em aberto still, note+heart present.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: DayEditorSheet(
            strings: const Strings(false),
            date: '2026-10-01',
            initialTaken: api.store['2026-10-01']?.taken,
            initialNotes: api.store['2026-10-01']?.notes ?? '',
            initialHeart: api.store['2026-10-01']?.heart ?? false,
            hadEntry: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    // No Taken/Missed selected.
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(segmented.selected, isEmpty);
  });

  testWidgets('tapping Taken commits status + notes + heart immediately',
      (tester) async {
    DayEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(false),
                    date: '2026-10-01',
                    initialTaken: null,
                    initialNotes: 'with note',
                    initialHeart: true,
                    hadEntry: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();

    expect(result?.clear, isFalse);
    expect(result?.taken, isTrue);
    expect(result?.notes, 'with note');
    expect(result?.heart, isTrue);
  });

  testWidgets('unselecting status clears existing mark immediately',
      (tester) async {
    DayEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(false),
                    date: '2026-10-01',
                    initialTaken: true,
                    initialNotes: '',
                    initialHeart: true,
                    hadEntry: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Clear mark'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    // Unselect Taken → autosave clear (no Save).
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    expect(result?.clear, isTrue);
  });

  testWidgets('note Done with existing status commits note + heart alone',
      (tester) async {
    DayEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(false),
                    date: '2026-10-01',
                    initialTaken: true,
                    initialNotes: '',
                    initialHeart: false,
                    hadEntry: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    await tester.enterText(find.byType(TextField), 'solo note');
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Done alone persists — no Taken/Missed re-tap, no Save.
    expect(result?.clear, isFalse);
    expect(result?.taken, isTrue);
    expect(result?.notes, 'solo note');
    expect(result?.heart, isTrue);
  });

  testWidgets(
      'onCommit: note Done persists without Taken/Missed re-tap (production path)',
      (tester) async {
    DayEditResult? committed;
    var commitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: true,
                    initialNotes: 'old',
                    initialHeart: false,
                    hadEntry: true,
                    onCommit: (result) {
                      commitCount++;
                      committed = result;
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'status unchanged');
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(commitCount, 1);
    expect(committed?.clear, isFalse);
    expect(committed?.taken, isTrue);
    expect(committed?.notes, 'status unchanged');
    expect(committed?.heart, isTrue);
    // Sheet closed — no Taken/Missed re-tap required.
    expect(find.text('Taken'), findsNothing);
  });

  testWidgets(
      'onCommit: heart-only Done persists with status left unchanged',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: false,
                    initialNotes: 'keep me',
                    initialHeart: false,
                    hadEntry: true,
                    onCommit: (result) => committed = result,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Note'));
    await tester.pumpAndSettle();
    // Heart only — leave note text alone, do not touch Missed.
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.taken, isFalse);
    expect(committed?.notes, 'keep me');
    expect(committed?.heart, isTrue);
  });

  testWidgets('onCommit: Taken still autosaves status + note + heart',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(false),
                    date: '2026-10-01',
                    initialTaken: null,
                    initialNotes: 'with note',
                    initialHeart: true,
                    hadEntry: true,
                    onCommit: (result) => committed = result,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Em aberto day already has note+heart; Taken commits all together.
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();

    expect(committed?.taken, isTrue);
    expect(committed?.notes, 'with note');
    expect(committed?.heart, isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'calendar heart indicator uses on-cell theme color ($brightness)',
      (tester) async {
        final now = DateTime.now();
        final date =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
        final scheme = buildApp217ColorScheme(
          brightness,
          palette: AppPalette.azure,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.azure,
            ),
            home: CalendarScreen(
              api: _HeartCalendarApi([
                Entry(date: date, taken: true, notes: 'n', heart: true),
              ]),
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
        );
        await tester.pumpAndSettle();
        final heart = tester.widget<Icon>(find.byIcon(Icons.favorite).first);
        // Pre-#25 red: heart matches filled-cell on-color, not #E11D48.
        expect(heart.color, isNot(const Color(0xFFE11D48)));
        expect(
          heart.color,
          App217Colors.onFilledCell(brightness, AppPalette.azure),
        );
        // Readable against the taken cell fill.
        final cell = App217Colors.cellTaken(brightness, AppPalette.azure);
        final contrast =
            (heart.color!.computeLuminance() - cell.computeLuminance()).abs();
        expect(contrast, greaterThan(0.2));
        // scheme.primary is used on the sheet; cell uses onFilledCell.
        expect(scheme.primary, isNot(const Color(0xFFE11D48)));
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Em aberto calendar cell shows note+heart without taken fill ($brightness)',
      (tester) async {
        final now = DateTime.now();
        final date =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.azure,
            ),
            home: CalendarScreen(
              api: _HeartCalendarApi([
                Entry(date: date, taken: null, notes: 'n', heart: true),
              ]),
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
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.favorite), findsWidgets);
        expect(find.byIcon(Icons.sticky_note_2_outlined), findsWidgets);
      },
    );
  }
}

class _HeartCalendarApi extends ApiClient {
  _HeartCalendarApi(this.entries) : super(AppConfig.fromEnvironment());

  final List<Entry> entries;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;

  @override
  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
  }) async =>
      Entry(date: date, taken: taken, notes: notes, heart: heart);

  @override
  Future<void> deleteEntry(String date) async {}
}
