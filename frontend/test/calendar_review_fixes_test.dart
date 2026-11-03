import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/day_summary.dart';
import 'package:a217/src/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api({this.gate, this.cycleGate, this.entries = const [], this.cycle})
      : super(AppConfig.fromEnvironment());

  /// Reads wait for these (a cold start, a slow network).
  final Future<void>? gate;
  final Future<void>? cycleGate;
  final List<Entry> entries;
  final CycleInfo? cycle;
  int listCalls = 0;
  final upserts = <Entry>[];

  @override
  Future<List<Entry>> listEntries(int year, int month) async {
    await gate;
    listCalls++;
    final prefix = '$year-${month.toString().padLeft(2, '0')}-';
    return [
      for (final e in entries)
        if (e.date.startsWith(prefix)) e,
    ];
  }

  @override
  Future<CycleInfo> getCycle(String today) async {
    await cycleGate;
    return cycle ?? CycleInfo.empty;
  }

  @override
  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
    bool period = false,
  }) async {
    final entry = Entry(
      date: date,
      taken: taken,
      notes: notes,
      heart: heart,
      period: period,
    );
    upserts.add(entry);
    return entry;
  }
}

const _owner = User(id: 'u1', email: 'o@example.invalid', name: 'O');
const _partner = User(id: 'p', email: 'p@example.invalid', name: 'P');
const _readOnly = ShareState(
  status: 'active',
  ownerName: 'Her',
  canEditCalendar: false,
);

final _today = DateTime(2026, 3, 15);
DateTime _clock() => DateTime(2026, 3, 15, 12);

Widget _app(
  Widget home, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: buildApp217Theme(
        brightness: brightness,
        palette: AppPalette.blue,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    );

CalendarScreen _calendar(
  _Api api, {
  User user = _owner,
  ShareState share = const ShareState(status: 'none'),
  AppLanguage language = AppLanguage.en,
  DateTime Function()? clock,
}) =>
    CalendarScreen(
      api: api,
      user: user,
      share: share,
      strings: Strings(language),
      onOpenSettings: () {},
      clock: clock ?? _clock,
    );

/// A phone-sized view with a device pixel ratio of 1.
void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

final _sheet = find.byKey(const ValueKey('expandable-day-sheet'));

CycleInfo get _cycleAround => CycleInfo(predictions: [
      CycleWindow(
        periodStart: _today.add(const Duration(days: 6)),
        periodEnd: _today.add(const Duration(days: 10)),
        pmsStart: _today.subtract(const Duration(days: 1)),
        pmsEnd: _today.add(const Duration(days: 5)),
      ),
    ]);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en');
  });

  testWidgets('a day whose month is not loaded yet is not editable until it is',
      (tester) async {
    _size(tester, const Size(412, 915));
    final gate = Completer<void>();
    final api = _Api(
      gate: gate.future,
      entries: [Entry(date: '2026-03-15', taken: true, notes: '')],
    );
    await tester.pumpWidget(_app(_calendar(api)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pump();
    expect(find.byType(DayEditorSheet), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);

    // The heart edit carries the Taken the server holds, not an empty status.
    await tester.tap(find.byKey(const ValueKey('day-heart-toggle')));
    await tester.pumpAndSettle();
    expect(api.upserts.single.taken, isTrue);
    expect(api.upserts.single.heart, isTrue);
  });

  testWidgets('the date rolling over reloads and drops the old today',
      (tester) async {
    _size(tester, const Size(412, 915));
    var now = DateTime(2026, 3, 15, 23, 59, 30);
    final api =
        _Api(entries: [Entry(date: '2026-03-15', taken: true, notes: '')]);
    await tester.pumpWidget(_app(_calendar(api, clock: () => now)));
    await tester.pumpAndSettle();
    expect(find.text('Taken'), findsOneWidget);
    final reads = api.listCalls;

    now = DateTime(2026, 3, 16, 0, 0, 5);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();

    expect(find.text('Taken'), findsNothing);
    expect(find.text('Open'), findsWidgets);
    expect(api.listCalls, greaterThan(reads));
  });

  testWidgets('an open sheet follows the cycle when it arrives',
      (tester) async {
    _size(tester, const Size(412, 915));
    final cycleGate = Completer<void>();
    final api = _Api(cycleGate: cycleGate.future, cycle: _cycleAround);
    await tester.pumpWidget(_app(_calendar(
      api,
      user: _partner,
      share: _readOnly,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-day-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-coming-period')), findsNothing);

    cycleGate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-coming-period')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-card-pms')), findsOneWidget);
  });

  for (final size in const [Size(360, 640), Size(320, 640)]) {
    for (final partner in [false, true]) {
      testWidgets(
          'open sheet tiles fit in Portuguese at $size, text 1.15'
          '${partner ? ' (partner)' : ''}', (tester) async {
        _size(tester, size);
        final api = _Api(
          cycle: _cycleAround,
          entries: [Entry(date: '2026-03-15', taken: true, notes: 'Uma nota')],
        );
        await tester.pumpWidget(_app(
          _calendar(
            api,
            user: partner ? _partner : _owner,
            share: partner ? _readOnly : const ShareState(status: 'none'),
            language: AppLanguage.pt,
          ),
          textScale: 1.15,
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(
            ValueKey(partner ? 'view-day-button' : 'update-day-button')));
        await tester.pumpAndSettle();
        await tester.drag(_sheet, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('day-coming-period')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('day cells describe the day to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    _size(tester, const Size(412, 915));
    final api = _Api(entries: [
      Entry(date: '2026-03-15', taken: true, notes: 'n', heart: true),
    ]);
    await tester.pumpWidget(_app(_calendar(api)));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'March 15.*Today.*Taken.*Sex.*Note')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('dismissing the note dialog keeps what was typed',
      (tester) async {
    DayEditResult? committed;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => DayEditorSheet(
              strings: const Strings(AppLanguage.en),
              date: '2026-10-01',
              initialTaken: null,
              initialNotes: '',
              hadEntry: false,
              onCommit: (result) => committed = result,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed and dismissed');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(committed?.notes, 'typed and dismissed');
  });

  testWidgets('CloseOnSignal closes its own route, not the one on top',
      (tester) async {
    final signal = ValueNotifier<int>(0);
    late BuildContext context;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    unawaited(showDialog<void>(
      context: context,
      builder: (_) => CloseOnSignal(signal: signal, child: const Text('own')),
    ));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
      context: context,
      builder: (_) => const Text('top'),
    ));
    await tester.pumpAndSettle();

    signal.value++;
    await tester.pumpAndSettle();
    expect(find.text('own'), findsNothing);
    expect(find.text('top'), findsOneWidget);
  });

  testWidgets('a note card that empties closes itself and nothing else',
      (tester) async {
    final notes = ValueNotifier<String>('hello');
    late BuildContext context;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      context = c;
      return const Text('home');
    })));
    unawaited(showDayNoteCard(context, title: 'Note', notes: notes));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    notes.value = '';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-note-card')), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  test('model helpers and wording', () {
    final none = CycleWindow(
      periodStart: _today,
      periodEnd: _today,
      pmsStart: DateTime(1),
      pmsEnd: DateTime(1),
    );
    expect(none.hasPms, isFalse);
    expect(CycleInfo(predictions: [none]).kindOf(_today),
        CycleDayKind.expectedPeriod);
    expect(
        isFutureDay(DateTime(2026, 3, 16), DateTime(2026, 3, 15, 23)), isTrue);
    expect(isFutureDay(DateTime(2026, 3, 15, 9), DateTime(2026, 3, 15, 8)),
        isFalse);
    const pt = Strings(AppLanguage.pt);
    expect(pt.taken, 'Tomada');
    expect(pt.missed, 'Perdida');
    expect(pt.pillNotLogged, pt.unrecorded);
  });
}
