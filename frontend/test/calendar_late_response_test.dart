import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

/// Serves the device's copy at once; the server answer waits on [gate].
///
/// This simulates the cold start on a slow network: the local store has
/// yesterday's picture, the server's answer (held back) differs.
class _DelayedServerApi extends ApiClient {
  _DelayedServerApi({required this.gate, required this.seededMonth})
      : super(AppConfig.fromEnvironment());

  final Completer<void> gate;
  final List<Entry> seededMonth;

  @override
  Future<List<Entry>?> cachedMonth(int year, int month) async => seededMonth;

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    await gate.future;
    return const [];
  }

  @override
  Future<CycleInfo> getCycle(String today) async => CycleInfo.empty;
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(brightness: Brightness.dark, palette: AppPalette.blue),
    home: CalendarScreen(
      api: api,
      user: const User(id: 'u1', email: 'o@example.invalid', name: 'O'),
      strings: const Strings(AppLanguage.en),
      onOpenSettings: () {},
    ),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('late network answer updates the calendar without input',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cachedDay = DateFormat('yyyy-MM-dd').format(today);
    final api = _DelayedServerApi(
      gate: Completer<void>(),
      seededMonth: [
        Entry(date: cachedDay, taken: true, notes: ''),
      ],
    );

    await _pump(tester, api);
    // First pumped frame: the cached copy is already on the grid, while the
    // server request is still waiting.
    await tester.pump();
    final grid = find.byKey(ValueKey('${now.year}-${now.month}'));
    expect(
      find.descendant(of: grid, matching: find.text('${now.day}')),
      findsOneWidget,
    );
    // Today's status comes from the cached entry, not a spinner.
    expect(find.text('Taken'), findsOneWidget);

    // The server finally answers — no tap, only frames passing.
    api.gate.complete();
    await tester.pump();
    await tester.pump();

    // The fresh (empty) month replaced the cached copy in place.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('Taken'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
