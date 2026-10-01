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
    required bool taken,
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
        expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
        expect(find.byIcon(Icons.favorite), findsOneWidget);
      },
    );
  }

  testWidgets('unselecting status keeps Save to clear existing mark',
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
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNotNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result?.clear, isTrue);
  });

  testWidgets('saving persists heart from note dialog', (tester) async {
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

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-heart-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result?.clear, isFalse);
    expect(result?.heart, isTrue);
    expect(result?.taken, isTrue);
  });
}
