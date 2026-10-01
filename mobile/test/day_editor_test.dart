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
  Future<Entry> upsertEntry(String date,
      {required bool taken, String notes = ''}) async {
    final e = Entry(date: date, taken: taken, notes: notes);
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
    await api.upsertEntry('2026-10-01', taken: true, notes: 'x');
    expect(api.store.containsKey('2026-10-01'), isTrue);
    await api.deleteEntry('2026-10-01');
    expect(api.store.containsKey('2026-10-01'), isFalse);
  });

  testWidgets('note icon sits on date row and opens dialog', (tester) async {
    final strings = const Strings(false);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.azure,
        ),
        home: Scaffold(
          body: DayEditorSheet(
            strings: strings,
            date: '2026-10-01',
            initialTaken: null,
            initialNotes: '',
            hadEntry: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('October 1, 2026'), findsOneWidget);
    // No orphan inline note field before opening the dialog.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello note');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    // Note affordance stays on the date row (filled icon after write).
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
  });

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
    // Unselect Taken in the segmented control.
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
}
