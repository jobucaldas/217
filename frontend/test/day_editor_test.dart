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
    bool period = false,
  }) async {
    final e = Entry(
      date: date,
      taken: taken,
      notes: notes,
      heart: heart,
      period: period,
    );
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
          palette: AppPalette.blue,
        );
        final strings = const Strings(AppLanguage.en);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.blue,
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
        expect(find.byKey(const ValueKey('note-heart-toggle')), findsNothing);
        // Cancel removed — outside/barrier dismisses.
        expect(find.text('Cancel'), findsNothing);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.style?.color, scheme.onSurface);
        final contrast = (field.style!.color!.computeLuminance() -
                scheme.surface.computeLuminance())
            .abs();
        expect(contrast, greaterThan(0.25));

        await tester.enterText(find.byType(TextField), 'hello note');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        // Embedded sheet (no modal): state updates in place; icons show.
        expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        final heartButton = tester.widget<IconButton>(find.descendant(
          of: find.byKey(const ValueKey('day-heart-toggle')),
          matching: find.byType(IconButton),
        ));
        // Bright red symbol, not the accent and not the period's pink.
        final red = App217Colors.intimacy(brightness);
        expect(
          heartButton.style?.foregroundColor?.resolve({WidgetState.selected}),
          red,
        );
        expect(red, isNot(App217Colors.period(brightness)));
        expect(red, isNot(scheme.primary));
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
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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
    // Pronto closes note dialog only — day sheet stays open.
    expect(find.text('Taken'), findsOneWidget);
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
  });

  testWidgets('Em aberto: heart alone persists without Taken/Missed',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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

    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.clear, isFalse);
    expect(committed?.taken, isNull);
    expect(committed?.notes, '');
    expect(committed?.heart, isTrue);
    // Pronto closes note dialog only — day sheet stays open with heart.
    expect(find.text('Taken'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsWidgets);
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
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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

    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keep me');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.taken, isNull);
    expect(api.store['2026-10-01']?.notes, 'keep me');
    expect(api.store['2026-10-01']?.heart, isTrue);
    expect(api.store['2026-10-01']?.taken, isNull);
    // Pronto left the day sheet open with note+heart — Em aberto still.
    expect(find.text('Taken'), findsOneWidget);
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsWidgets);
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
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(AppLanguage.en),
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
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(AppLanguage.en),
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

  testWidgets('heart toggle with existing status commits the heart',
      (tester) async {
    DayEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<DayEditResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const DayEditorSheet(
                    strings: Strings(AppLanguage.en),
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

    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();

    // The toggle alone persists — no Taken/Missed re-tap, no Save.
    expect(result?.clear, isFalse);
    expect(result?.taken, isTrue);
    expect(result?.notes, '');
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
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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

    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'status unchanged');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // One commit for the heart, one for the note.
    expect(commitCount, 2);
    expect(committed?.clear, isFalse);
    expect(committed?.taken, isTrue);
    expect(committed?.notes, 'status unchanged');
    expect(committed?.heart, isTrue);
    // Pronto closes note dialog only — day sheet stays open for Taken/Missed.
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsWidgets);
  });

  testWidgets(
      'onCommit: heart-only Done persists with status left unchanged',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.dark,
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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

    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note'));
    await tester.pumpAndSettle();
    // Heart only — leave note text alone, do not touch Missed.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(committed?.taken, isFalse);
    expect(committed?.notes, 'keep me');
    expect(committed?.heart, isTrue);
    // Day sheet remains so Missed/Taken can still be tapped.
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
  });

  testWidgets('onCommit: Taken still autosaves status + note + heart',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayEditorSheet(
                    strings: const Strings(AppLanguage.en),
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
    testWidgets('empty note button has no plus badge ($brightness)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: brightness,
            palette: AppPalette.blue,
          ),
          home: Scaffold(
            body: DayEditorSheet(
              strings: const Strings(AppLanguage.en),
              date: '2026-10-01',
              initialTaken: null,
              initialNotes: '',
              initialHeart: false,
              hadEntry: false,
              onCommit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'onCommit: Pronto keeps day sheet open for Taken ($brightness)',
      (tester) async {
        final commits = <DayEditResult>[];
        const strings = Strings(AppLanguage.en);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.blue,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => DayEditorSheet(
                        strings: strings,
                        date: '2026-10-01',
                        initialTaken: null,
                        initialNotes: '',
                        initialHeart: false,
                        hadEntry: false,
                        onCommit: commits.add,
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

        await tester.tap(find.byTooltip(strings.addNote));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'stay open');
        await tester.tap(find.text(strings.done));
        await tester.pumpAndSettle();

        expect(commits, hasLength(1));
        expect(commits.single.taken, isNull);
        expect(commits.single.notes, 'stay open');
        // Note dialog gone; day sheet still shows status buttons.
        expect(find.byType(TextField), findsNothing);
        expect(find.text(strings.takenLabel), findsOneWidget);
        expect(find.text(strings.missedLabel), findsOneWidget);

        // Can tap Taken without reopening the day card.
        await tester.tap(find.text(strings.takenLabel));
        await tester.pumpAndSettle();
        expect(commits, hasLength(2));
        expect(commits.last.taken, isTrue);
        expect(commits.last.notes, 'stay open');
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'calendar heart indicator uses on-cell theme color ($brightness)',
      (tester) async {
        final now = DateTime.now();
        final date =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
        final scheme = buildApp217ColorScheme(
          brightness,
          palette: AppPalette.blue,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.blue,
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
              strings: const Strings(AppLanguage.en),
              onOpenSettings: () {},
              palette: AppPalette.blue,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heart = tester.widget<Icon>(find.byIcon(Icons.favorite).first);
        // Pre-#25 red: heart matches filled-cell on-color, not #E11D48.
        expect(heart.color, isNot(const Color(0xFFE11D48)));
        expect(
          heart.color,
          App217Colors.onFilledCell(brightness, AppPalette.blue),
        );
        // Readable against the taken cell fill.
        final cell = App217Colors.cellTaken(brightness, AppPalette.blue);
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
              palette: AppPalette.blue,
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
              strings: const Strings(AppLanguage.en),
              onOpenSettings: () {},
              palette: AppPalette.blue,
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
