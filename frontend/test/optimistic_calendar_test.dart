import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

/// Server that answers writes only when the test lets it.
class _SlowApi extends ApiClient {
  _SlowApi() : super(AppConfig.fromEnvironment());

  final stored = <String, Entry>{};
  Completer<void>? writeGate;
  Object? writeError;
  Completer<void>? listGate;
  int listCalls = 0;
  int cycleCalls = 0;

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    listCalls++;
    final gate = listGate;
    if (gate != null) await gate.future;
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    return [
      for (final e in stored.values)
        if (e.date.startsWith(prefix)) e,
    ];
  }

  @override
  Future<CycleInfo> getCycle(String today) async {
    cycleCalls++;
    return CycleInfo.empty;
  }

  @override
  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
    bool period = false,
  }) async {
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    final entry = Entry(
      date: date,
      taken: taken,
      notes: notes,
      heart: heart,
      period: period,
    );
    stored[date] = entry;
    return entry;
  }

  @override
  Future<void> deleteEntry(String date) async {
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    stored.remove(date);
  }
}

Future<void> _pumpCalendar(WidgetTester tester, _SlowApi api) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(
      brightness: Brightness.dark,
      palette: AppPalette.blue,
    ),
    home: CalendarScreen(
      api: api,
      user: const User(id: 'u1', email: 'o@example.invalid', name: 'O'),
      strings: const Strings(AppLanguage.en),
      onOpenSettings: () {},
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapTakenOnToday(WidgetTester tester) async {
  final now = DateTime.now();
  final grid = find.byKey(ValueKey('${now.year}-${now.month}'));
  await tester.tap(
    find.descendant(of: grid, matching: find.text('${now.day}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Taken').last);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Taken shows at once, before the server answers', (tester) async {
    final api = _SlowApi()..writeGate = Completer<void>();
    await _pumpCalendar(tester, api);
    // Header status and legend.
    expect(find.text('Open'), findsNWidgets(2));
    final listCallsBefore = api.listCalls;

    await _tapTakenOnToday(tester);
    await tester.pumpAndSettle();

    // Sheet closed and today's status flipped while the POST is still held.
    expect(api.stored, isEmpty);
    expect(find.text('Open'), findsOneWidget);

    api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(api.stored.values.single.taken, isTrue);
    expect(find.text('Open'), findsOneWidget);
    // Saved entries are not fetched again, only the predictions.
    expect(api.listCalls, listCallsBefore);
    expect(api.cycleCalls, greaterThan(1));
  });

  testWidgets('failed save rolls back and shows the error', (tester) async {
    final api = _SlowApi()
      ..writeError = ApiException(
        'upsert entry',
        http.Response('{"error":"boom"}', 500),
      );
    await _pumpCalendar(tester, api);

    await _tapTakenOnToday(tester);
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
  });

  testWidgets('a saved day is still there when the month is revisited '
      'before the refresh answers', (tester) async {
    final api = _SlowApi();
    await _pumpCalendar(tester, api);
    await _tapTakenOnToday(tester);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);

    api.listGate = Completer<void>();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    // Both refreshes are held; the month comes from memory.
    expect(find.text('Open'), findsOneWidget);
    api.listGate!.complete();
    await tester.pumpAndSettle();
  });
}
