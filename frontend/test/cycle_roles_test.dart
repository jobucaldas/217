import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/partner_alerts_screen.dart';
import 'package:a217/src/screens/role_screen.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/screens/share_screens.dart';
import 'package:a217/src/theme/app_theme.dart';
import 'package:a217/src/theme/contrast.dart';

const _en = Strings(AppLanguage.en);

DateTime _d(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day + days);

/// Today sits inside a predicted PMS window; the period follows.
CycleInfo _cycleAround(DateTime today) => CycleInfo(
      estimated: false,
      periodStarts: [_d(today, -25)],
      predictions: [
        CycleWindow(
          periodStart: _d(today, 3),
          periodEnd: _d(today, 7),
          pmsStart: _d(today, -2),
          pmsEnd: _d(today, 2),
        ),
      ],
    );

class _CycleApi extends ApiClient {
  _CycleApi({this.entries = const [], CycleInfo? cycle, this.cycleError})
      : cycle = cycle ?? CycleInfo.empty,
        super(AppConfig.fromEnvironment());

  final List<Entry> entries;
  CycleInfo cycle;
  int cycleCalls = 0;
  Completer<CycleInfo>? cycleCompleter;
  Completer<PartnerAlertPreference>? alertCompleter;
  final Object? cycleError;
  final List<Completer<CycleInfo>> cycleRequests = [];
  String? role;
  PartnerAlertPreference alerts = const PartnerAlertPreference();
  final saves = <PartnerAlertPreference>[];
  Duration? saveDelay;
  Object? saveError;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;

  @override
  Future<CycleInfo> getCycle(String today) {
    cycleCalls++;
    if (cycleError != null) return Future.error(cycleError!);
    if (cycleRequests.length >= cycleCalls) {
      return cycleRequests[cycleCalls - 1].future;
    }
    return cycleCompleter?.future ?? Future.value(cycle);
  }

  @override
  Future<PartnerAlertPreference> getPartnerAlerts() =>
      alertCompleter?.future ?? Future.value(alerts);

  @override
  Future<PartnerAlertPreference> savePartnerAlerts(
    PartnerAlertPreference pref,
  ) async {
    saves.add(pref);
    if (saveDelay != null) await Future<void>.delayed(saveDelay!);
    if (saveError != null) throw saveError!;
    return alerts = pref;
  }

  @override
  Future<SessionSnapshot> setRole(String role) async {
    this.role = role;
    return SessionSnapshot(
      user: User(id: 'u1', email: 'a@b.c', name: 'A', role: role),
      share: ShareState(status: 'none', canEditCalendar: role == 'owner'),
    );
  }
}

Widget _app(Brightness brightness, Widget home) => MaterialApp(
      theme: buildApp217Theme(brightness: brightness, palette: AppPalette.blue),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('CycleInfo', () {
    test('parses server JSON and classifies days', () {
      final info = CycleInfo.fromJson({
        'cycle_length': 30,
        'period_length': 4,
        'estimated': false,
        'period_starts': ['2026-09-29'],
        'predictions': [
          {
            'period_start': '2026-10-29',
            'period_end': '2026-11-01',
            'pms_start': '2026-10-24',
            'pms_end': '2026-10-28',
          },
        ],
      });
      expect(info.cycleLength, 30);
      expect(info.kindOf(DateTime(2026, 10, 23)), CycleDayKind.none);
      expect(info.kindOf(DateTime(2026, 10, 24)), CycleDayKind.pms);
      expect(info.kindOf(DateTime(2026, 10, 28, 15)), CycleDayKind.pms);
      expect(info.kindOf(DateTime(2026, 11, 1)), CycleDayKind.predictedPeriod);
      expect(info.nextWindow(DateTime(2026, 11, 1))?.periodStart,
          DateTime(2026, 10, 29));
      expect(info.nextWindow(DateTime(2026, 11, 2)), isNull);
    });
    test('menopause empty PMS dates never classify days', () {
      final info = CycleInfo.fromJson({
        'note': 'pms_suppressed_menopause',
        'predictions': [
          {
            'period_start': '2026-10-29',
            'period_end': '2026-11-02',
            'pms_start': '',
            'pms_end': ''
          },
        ],
      });
      expect(info.note, 'pms_suppressed_menopause');
      expect(info.kindOf(DateTime(2026, 10, 28)), CycleDayKind.none);
      expect(info.kindOf(DateTime(2026, 10, 29)), CycleDayKind.predictedPeriod);
    });
  });

  group('partner alert plan', () {
    final now = DateTime(2026, 10, 3, 12);
    final cycle = CycleInfo(predictions: [
      CycleWindow(
        periodStart: DateTime(2026, 10, 12),
        periodEnd: DateTime(2026, 10, 16),
        pmsStart: DateTime(2026, 10, 7),
        pmsEnd: DateTime(2026, 10, 11),
      ),
      CycleWindow(
        periodStart: DateTime(2026, 11, 9),
        periodEnd: DateTime(2026, 11, 13),
        pmsStart: DateTime(2026, 11, 4),
        pmsEnd: DateTime(2026, 11, 8),
      ),
    ]);
    List<PlannedAlert> plan(PartnerAlertPreference pref,
            {bool logged = false}) =>
        planPartnerAlerts(
          now: now,
          pref: pref,
          cycle: cycle,
          todayLogged: logged,
          pmsTitle: (_) => 'pms',
          pmsBody: (w) => 'pms ${w.periodStart.day}',
          pillTitle: 'pill',
          pillBody: 'pill body',
        );

    test('nothing when both toggles are off', () {
      expect(plan(const PartnerAlertPreference()), isEmpty);
    });

    test('PMS alerts fire on each predicted PMS start at their own time', () {
      final alerts = plan(const PartnerAlertPreference(
        pmsEnabled: true,
        pmsTime: '08:30',
      ));
      expect(alerts.map((a) => a.when), [
        DateTime(2026, 10, 7, 8, 30),
        DateTime(2026, 11, 4, 8, 30),
      ]);
      expect(alerts.first.body, 'pms 12');
      expect(alerts.map((a) => a.id).toSet().length, 2);
    });
    test('empty PMS windows do not notify but pill alerts remain', () {
      final noPms = CycleInfo(predictions: [
        CycleWindow(
          periodStart: DateTime(2026, 10, 12),
          periodEnd: DateTime(2026, 10, 16),
          pmsStart: DateTime(1),
          pmsEnd: DateTime(1),
        ),
      ]);
      final alerts = planPartnerAlerts(
        now: now,
        pref: const PartnerAlertPreference(pmsEnabled: true, pillEnabled: true),
        cycle: noPms,
        todayLogged: false,
        pmsTitle: (_) => 'pms',
        pmsBody: (_) => 'pms',
        pillTitle: 'pill',
        pillBody: 'pill',
      );
      expect(alerts.where((a) => a.title == 'pms'), isEmpty);
      expect(alerts.where((a) => a.title == 'pill'), isNotEmpty);
    });

    test('year-one empty PMS is skipped while a real future window remains',
        () {
      final alerts = planPartnerAlerts(
        now: DateTime(1, 1, 1, 8),
        pref: const PartnerAlertPreference(pmsEnabled: true, pmsTime: '09:00'),
        cycle: CycleInfo(predictions: [
          CycleWindow(
            periodStart: DateTime(1, 1, 6),
            periodEnd: DateTime(1, 1, 10),
            pmsStart: DateTime(1),
            pmsEnd: DateTime(1),
          ),
          CycleWindow(
            periodStart: DateTime(2, 1, 7),
            periodEnd: DateTime(2, 1, 11),
            pmsStart: DateTime(2, 1, 2),
            pmsEnd: DateTime(2, 1, 6),
          ),
        ]),
        todayLogged: false,
        pmsTitle: (_) => 'pms',
        pmsBody: (window) => window.periodStart.day.toString(),
        pillTitle: 'pill',
        pillBody: 'pill',
      );
      expect(alerts, hasLength(1));
      expect(alerts.single.when, DateTime(2, 1, 2, 9));
      expect(alerts.single.body, '7');
    });

    test('pill alerts skip today once logged and past times', () {
      const pref = PartnerAlertPreference(pillEnabled: true, pillTime: '21:00');
      final open = plan(pref);
      expect(open.first.when, DateTime(2026, 10, 3, 21));
      expect(open.length, pillAlertHorizonDays);
      final logged = plan(pref, logged: true);
      expect(logged.first.when, DateTime(2026, 10, 4, 21));
      expect(logged.length, pillAlertHorizonDays - 1);
      final early = plan(const PartnerAlertPreference(
        pillEnabled: true,
        pillTime: '09:00',
      ));
      expect(early.first.when, DateTime(2026, 10, 4, 9));
    });

    group('pill repeat', () {
      List<PlannedAlert> repeatsForDay(List<PlannedAlert> alerts, int day) {
        final base = partnerPillRepeatIdBase + day * maxPillRepeatsPerDay;
        return alerts.where((a) => a.id >= base && a.id < base + maxPillRepeatsPerDay).toList()
          ..sort((a, b) => a.when.compareTo(b.when));
      }

      test('disabled by default even with the base alert on', () {
        final alerts = plan(const PartnerAlertPreference(pillEnabled: true));
        expect(alerts.every((a) => a.id < partnerPillRepeatIdBase), isTrue);
      });

      test('fires every X minutes after the pill time, capped at 23:59', () {
        const pref = PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatEnabled: true,
          pillRepeatMinutes: 30,
        );
        final day0 = repeatsForDay(plan(pref), 0);
        expect(day0.map((a) => a.when), [
          DateTime(2026, 10, 3, 21, 30),
          DateTime(2026, 10, 3, 22, 0),
          DateTime(2026, 10, 3, 22, 30),
          DateTime(2026, 10, 3, 23, 0),
          DateTime(2026, 10, 3, 23, 30),
        ]);
        // Never rolls into the next day (24:00 would be the 6th occurrence).
        expect(day0.every((a) => a.when.day == 3), isTrue);
      });

      test('stops once today is logged, future days stay scheduled', () {
        const pref = PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatEnabled: true,
          pillRepeatMinutes: 30,
        );
        final alerts = plan(pref, logged: true);
        expect(repeatsForDay(alerts, 0), isEmpty);
        expect(repeatsForDay(alerts, 1), isNotEmpty);
      });

      test('per-day count is bounded even at a 1-minute interval', () {
        final alerts = planPartnerAlerts(
          now: DateTime(2026, 10, 3),
          pref: const PartnerAlertPreference(
            pillEnabled: true,
            pillTime: '00:00',
            pillRepeatEnabled: true,
            pillRepeatMinutes: 1,
          ),
          cycle: CycleInfo.empty,
          todayLogged: false,
          pmsTitle: (_) => 'pms',
          pmsBody: (_) => 'pms',
          pillTitle: 'pill',
          pillBody: 'pill',
        );
        expect(repeatsForDay(alerts, 0).length, maxPillRepeatsPerDay);
      });

      test('not queued beyond the repeat horizon even at a 1-minute interval',
          () {
        final alerts = planPartnerAlerts(
          now: DateTime(2026, 10, 3),
          pref: const PartnerAlertPreference(
            pillEnabled: true,
            pillTime: '00:00',
            pillRepeatEnabled: true,
            pillRepeatMinutes: 1,
          ),
          cycle: CycleInfo.empty,
          todayLogged: false,
          pmsTitle: (_) => 'pms',
          pmsBody: (_) => 'pms',
          pillTitle: 'pill',
          pillBody: 'pill',
        );
        final totalRepeats =
            alerts.where((a) => a.id >= partnerPillRepeatIdBase).length;
        expect(totalRepeats, lessThanOrEqualTo(96));
        expect(totalRepeats, pillRepeatHorizonDays * maxPillRepeatsPerDay);
        for (var d = pillRepeatHorizonDays; d < pillAlertHorizonDays; d++) {
          expect(repeatsForDay(alerts, d), isEmpty, reason: 'day $d');
        }
      });

      test('ids are unique and stay within their reserved ranges', () {
        const pref = PartnerAlertPreference(
          pmsEnabled: true,
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatEnabled: true,
          pillRepeatMinutes: 15,
        );
        final ids = plan(pref).map((a) => a.id).toList();
        expect(ids.toSet().length, ids.length);
        for (final id in ids) {
          final inPms =
              id >= partnerPmsIdBase && id < partnerPmsIdBase + partnerAlertIdCount;
          final inPill =
              id >= partnerPillIdBase && id < partnerPillIdBase + partnerAlertIdCount;
          final inRepeat = id >= partnerPillRepeatIdBase &&
              id < partnerPillRepeatIdBase + partnerPillRepeatIdCount;
          expect(inPms || inPill || inRepeat, isTrue, reason: 'id $id');
        }
      });

      test('replanning the same inputs twice is idempotent', () {
        const pref = PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatEnabled: true,
          pillRepeatMinutes: 15,
        );
        final first = plan(pref);
        final second = plan(pref);
        expect(first.map((a) => a.id), second.map((a) => a.id));
        expect(first.map((a) => a.when), second.map((a) => a.when));
      });
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('role choice: two readable options, owner pick ($brightness)',
        (tester) async {
      final api = _CycleApi();
      SessionSnapshot? chosen;
      await tester.pumpWidget(_app(
        brightness,
        RoleChoiceScreen(
          api: api,
          strings: _en,
          onChosen: (s) => chosen = s,
          onOpenSettings: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final scheme =
          Theme.of(tester.element(find.text('I take the pill'))).colorScheme;
      for (final label in ['I take the pill', "I'm the partner"]) {
        final text = tester.widget<Text>(find.text(label));
        expect(meetsBodyContrast(text.style!.color!, scheme.surface), isTrue,
            reason: label);
      }
      await tester.tap(find.byKey(const ValueKey('role-owner')));
      await tester.pumpAndSettle();
      expect(api.role, 'owner');
      expect(chosen?.user?.isOwner, isTrue);
    });

    testWidgets('partner join screen (not yet linked) ($brightness)',
        (tester) async {
      var switched = false;
      await tester.pumpWidget(_app(
        brightness,
        PartnerJoinScreen(
          api: _CycleApi(),
          strings: _en,
          onJoined: (_) {},
          onAccountDeleted: () {},
          onOpenSettings: () {},
          onSwitchToOwner: () => switched = true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Join her calendar'), findsOneWidget);
      expect(
          find.text('You are not invited to her 217 calendar'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('switch-to-owner')));
      expect(switched, isTrue);
    });

    testWidgets(
        'calendar draws PMS ring, period drops and cycle line '
        '($brightness)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = _d(today, -1);
      String key(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final api = _CycleApi(
        cycle: _cycleAround(today),
        entries: [
          Entry(date: key(yesterday), taken: true, notes: '', period: true)
        ],
      );
      await tester.pumpWidget(_app(
        brightness,
        CalendarScreen(
          api: api,
          user: const User(
              id: 'u2', email: 'bf@b.c', name: 'Bf', role: 'partner'),
          share: const ShareState(
            status: 'active',
            ownerName: 'Her',
            canEditCalendar: false,
          ),
          strings: _en,
          onOpenSettings: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final line = find.byKey(const ValueKey('cycle-line'));
      expect(line, findsOneWidget);
      expect(
        find.descendant(
            of: line, matching: find.textContaining('PMS likely now')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsWidgets);
      final inPeriod = _d(today, 4);
      expect(
        find.byKey(
            ValueKey('predicted-period-${inPeriod.month}-${inPeriod.day}')),
        findsWidgets,
      );
      if (yesterday.month == today.month) {
        expect(
          find.byKey(ValueKey('period-${yesterday.month}-${yesterday.day}')),
          findsWidgets,
        );
      }
      // Legend explains both marks.
      expect(find.text('Period'), findsOneWidget);
      expect(find.text('PMS'), findsOneWidget);
    });

    testWidgets(
        'menopause suppresses PMS ring and shows translated note ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final cycle = CycleInfo(note: 'pms_suppressed_menopause', predictions: [
        CycleWindow(
            periodStart: _d(today, 3),
            periodEnd: _d(today, 7),
            pmsStart: DateTime(1),
            pmsEnd: DateTime(1)),
      ]);
      await tester.pumpWidget(_app(
          brightness,
          CalendarScreen(
            api: _CycleApi(cycle: cycle),
            user: const User(id: 'o', email: 'o@example.com', name: 'Owner'),
            share: const ShareState(status: 'none'),
            strings: _en,
            onOpenSettings: () {},
          )));
      await tester.pumpAndSettle();
      expect(find.textContaining('217 counts no PMS'), findsOneWidget);
      final line = find.byKey(const ValueKey('cycle-line'));
      expect(line, findsOneWidget);
      expect(find.textContaining('Next period ~'), findsOneWidget);
      expect(find.textContaining('0001'), findsNothing);
      expect(find.byKey(const ValueKey('cycle-stage-note')), findsOneWidget);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsNothing);
    });

    testWidgets('perimenopause keeps PMS ring and shows note ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await tester.pumpWidget(_app(
          brightness,
          CalendarScreen(
            api: _CycleApi(
                cycle:
                    CycleInfo(note: 'pms_counted_perimenopause', predictions: [
              CycleWindow(
                  periodStart: _d(today, 3),
                  periodEnd: _d(today, 7),
                  pmsStart: _d(today, -2),
                  pmsEnd: _d(today, 2)),
            ])),
            user: const User(id: 'o', email: 'o@example.com', name: 'Owner'),
            share: const ShareState(status: 'none'),
            strings: _en,
            onOpenSettings: () {},
          )));
      await tester.pumpAndSettle();
      expect(find.textContaining('perimenopause. Cycles can still happen'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-stage-note')), findsOneWidget);
      expect(find.textContaining('PMS likely now'), findsOneWidget);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsWidgets);
    });

    testWidgets('stage signal reloads cached cycle data ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final api = _CycleApi(cycle: _cycleAround(today));
      final stageChanges = ValueNotifier<int>(0);
      addTearDown(stageChanges.dispose);
      var generation = 0;
      await tester.pumpWidget(_app(
          brightness,
          CalendarScreen(
            api: api,
            user: const User(id: 'o', email: 'o@example.com', name: 'Owner'),
            share: const ShareState(status: 'none'),
            strings: _en,
            onOpenSettings: () {},
            cycleRefreshSignal: stageChanges,
            sessionGeneration: () => generation,
            isSessionCurrent: (g, _) => g == generation,
          )));
      await tester.pumpAndSettle();
      expect(api.cycleCalls, 1);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsWidgets);

      api.cycle = CycleInfo(
        note: 'pms_suppressed_menopause',
        predictions: [
          CycleWindow(
            periodStart: _d(today, 3),
            periodEnd: _d(today, 7),
            pmsStart: DateTime(1),
            pmsEnd: DateTime(1),
          ),
        ],
      );
      // The app bumps its session generation right before signalling.
      generation++;
      stageChanges.value++;
      await tester.pumpAndSettle();
      expect(api.cycleCalls, 2);
      expect(find.byKey(const ValueKey('cycle-stage-note')), findsOneWidget);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsNothing);
    });

    testWidgets('stale cycle response cannot replace latest data ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final api = _CycleApi()
        ..cycleRequests
            .addAll([Completer<CycleInfo>(), Completer<CycleInfo>()]);
      final stageChanges = ValueNotifier<int>(0);
      addTearDown(stageChanges.dispose);
      await tester.pumpWidget(_app(
          brightness,
          CalendarScreen(
            api: api,
            user: const User(id: 'o', email: 'o@example.com', name: 'Owner'),
            share: const ShareState(status: 'none'),
            strings: _en,
            onOpenSettings: () {},
            cycleRefreshSignal: stageChanges,
          )));
      await tester.pump();
      expect(api.cycleCalls, 1);

      api.cycleRequests[1].complete(CycleInfo(
        note: 'pms_suppressed_menopause',
        predictions: [
          CycleWindow(
            periodStart: _d(today, 3),
            periodEnd: _d(today, 7),
            pmsStart: DateTime(1),
            pmsEnd: DateTime(1),
          )
        ],
      ));
      stageChanges.value++;
      await tester.pump();
      expect(api.cycleCalls, 2);
      await tester.pumpAndSettle();
      expect(find.textContaining('217 counts no PMS'), findsOneWidget);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsNothing);

      api.cycleRequests[0].complete(CycleInfo(
        note: 'pms_counted_perimenopause',
        predictions: [_cycleAround(today).predictions.single],
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('217 counts no PMS'), findsOneWidget);
      expect(find.textContaining('perimenopause. Cycles can still happen'),
          findsNothing);
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsNothing);
    });

    testWidgets(
        'menopause without predictions omits the PMS hint ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(
          brightness,
          CalendarScreen(
            key: const ValueKey('menopause-no-history'),
            api: _CycleApi(
                cycle: const CycleInfo(note: 'pms_suppressed_menopause')),
            user: const User(id: 'o', email: 'o@example.com', name: 'Owner'),
            share: const ShareState(status: 'none'),
            strings: _en,
            onOpenSettings: () {},
          )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-line')), findsNothing);
      expect(find.byKey(const ValueKey('cycle-stage-note')), findsOneWidget);
      expect(
          find.text('Mark period days to see PMS predictions'), findsNothing);
    });

    testWidgets(
        'owner without period history gets the marking hint '
        '($brightness)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(
        brightness,
        CalendarScreen(
          api: _CycleApi(),
          user: const User(id: 'u1', email: 'a@b.c', name: 'A'),
          strings: _en,
          onOpenSettings: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text('Mark period days to see PMS predictions'), findsOneWidget);
    });

    testWidgets('day sheet period toggle saves and stays open ($brightness)',
        (tester) async {
      final commits = <DayEditResult>[];
      await tester.pumpWidget(_app(
        brightness,
        Scaffold(
          body: DayEditorSheet(
            strings: _en,
            date: '2026-10-01',
            initialTaken: null,
            initialNotes: '',
            hadEntry: false,
            onCommit: commits.add,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final chip = find.byKey(const ValueKey('day-period-toggle'));
      // Sits in the header beside the notes button, not on its own row.
      final notes = find.byTooltip('Note');
      expect(
        (tester.getCenter(chip).dy - tester.getCenter(notes).dy).abs(),
        lessThan(1),
      );
      expect(find.byTooltip('Period'), findsOneWidget);
      final heart = find.byKey(const ValueKey('day-heart-toggle'));
      expect(
        (tester.getCenter(heart).dy - tester.getCenter(notes).dy).abs(),
        lessThan(1),
      );
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.water_drop)),
          findsNothing);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.water_drop)),
          findsOneWidget);
      expect(commits.single.period, isTrue);
      expect(commits.single.taken, isNull);
      expect(find.byKey(const ValueKey('day-period-toggle')), findsOneWidget);

      // Unmarking the only data on the day clears it.
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(commits.last.clear, isTrue);
    });

    testWidgets('partner alerts: separate toggles and times ($brightness)',
        (tester) async {
      final api = _CycleApi();
      final scheduled = <PartnerAlertPreference>[];
      await tester.pumpWidget(_app(
        brightness,
        PartnerAlertsScreen(
          api: api,
          strings: _en,
          share: const ShareState(status: 'active', ownerName: 'Her'),
          reschedule: (pref) async {
            scheduled.add(pref);
            return LocalReminderSyncStatus.scheduled;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PMS heads-up'), findsOneWidget);
      expect(find.text('Pill not logged'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text(_en.pmsNotCounted), findsNothing);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('alert-pill')),
        matching: find.byType(Switch),
      ).first);
      await tester.pumpAndSettle();
      expect(api.saves.last.pillEnabled, isTrue);
      expect(api.saves.last.pmsEnabled, isFalse);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('alert-pms')),
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(api.saves.last.pmsEnabled, isTrue);
      expect(api.saves.last.pillEnabled, isTrue);
      expect(scheduled.length, 2);

      final scheme =
          Theme.of(tester.element(find.text('PMS heads-up'))).colorScheme;
      final time = tester.widget<Text>(find.text('09:00'));
      expect(meetsBodyContrast(time.style!.color!, scheme.surface), isTrue);
    });

    testWidgets('pill repeat: toggling shows the field, validates, saves '
        '($brightness)', (tester) async {
      final api = _CycleApi()
        ..alerts = const PartnerAlertPreference(pillEnabled: true);
      await tester.pumpWidget(_app(
        brightness,
        PartnerAlertsScreen(
          api: api,
          strings: _en,
          share: const ShareState(status: 'active', ownerName: 'Her'),
          reschedule: (_) async => LocalReminderSyncStatus.scheduled,
        ),
      ));
      await tester.pumpAndSettle();

      final repeatToggle = find.byKey(const ValueKey('pill-repeat-toggle'));
      final minutesField =
          find.byKey(const ValueKey('pill-repeat-minutes-field'));
      expect(repeatToggle, findsOneWidget);
      expect(minutesField, findsNothing);

      await tester.tap(find.descendant(
        of: repeatToggle,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(api.saves.last.pillRepeatEnabled, isTrue);
      expect(api.saves.last.pillRepeatMinutes, 15);
      expect(minutesField, findsOneWidget);
      expect(find.text(_en.pillRepeatRangeError), findsNothing);
      expect(find.text(_en.pillRepeatHelper(15)), findsOneWidget);

      for (final invalid in ['0', '121', '']) {
        final savesBefore = api.saves.length;
        await tester.enterText(minutesField, invalid);
        await tester.pumpAndSettle();
        // Error renders as its own full-width line, not clipped inside the
        // narrow minutes field, and replaces the helper line while invalid.
        expect(find.text(_en.pillRepeatRangeError), findsOneWidget);
        expect(
          find.descendant(
            of: minutesField,
            matching: find.text(_en.pillRepeatRangeError),
          ),
          findsNothing,
        );
        expect(find.text(_en.pillRepeatHelper(15)), findsNothing);
        expect(api.saves.length, savesBefore, reason: 'invalid: $invalid');
      }

      await tester.enterText(minutesField, '45');
      await tester.pump();
      // Saving the typed minutes is debounced; nothing is sent yet.
      expect(find.text(_en.pillRepeatRangeError), findsNothing);
      expect(api.saves.last.pillRepeatMinutes, 15);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text(_en.pillRepeatRangeError), findsNothing);
      expect(find.text(_en.pillRepeatHelper(45)), findsOneWidget);
      expect(api.saves.last.pillRepeatMinutes, 45);
      expect(api.saves.last.pillRepeatEnabled, isTrue);

      await tester.tap(find.descendant(
        of: repeatToggle,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(api.saves.last.pillRepeatEnabled, isFalse);
      expect(minutesField, findsNothing);
    });

    testWidgets(
        'pill repeat minutes: digits typed quickly debounce to a single '
        'save and the field stays editable while a save is in flight '
        '($brightness)', (tester) async {
      final api = _CycleApi()
        ..alerts = const PartnerAlertPreference(pillEnabled: true)
        ..saveDelay = const Duration(seconds: 2);
      await tester.pumpWidget(_app(
        brightness,
        PartnerAlertsScreen(
          api: api,
          strings: _en,
          share: const ShareState(status: 'active', ownerName: 'Her'),
          reschedule: (_) async => LocalReminderSyncStatus.scheduled,
        ),
      ));
      await tester.pumpAndSettle();

      final repeatToggle = find.byKey(const ValueKey('pill-repeat-toggle'));
      final minutesField =
          find.byKey(const ValueKey('pill-repeat-minutes-field'));

      // Enabling the toggle kicks off a slow save (still in flight below).
      await tester.tap(find.descendant(
        of: repeatToggle,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      expect(minutesField, findsOneWidget);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      // Two keystrokes land well inside the debounce window; the field must
      // never lock up because of the toggle's own in-flight save.
      await tester.enterText(minutesField, '4');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);
      expect(api.saves.any((p) => p.pillRepeatMinutes == 45), isFalse);

      await tester.enterText(minutesField, '45');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);
      expect(api.saves.any((p) => p.pillRepeatMinutes == 45), isFalse);

      // The debounce elapses, but the minutes save queues behind the
      // toggle's still in-flight save rather than racing it.
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.saves.any((p) => p.pillRepeatMinutes == 45), isFalse);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      // Once the toggle's save finishes, the queued minutes save fires.
      await tester.pump(const Duration(seconds: 2));
      expect(api.saves.where((p) => p.pillRepeatMinutes == 45).length, 1);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
        'pill repeat minutes: a failed save restores the previous value '
        '($brightness)', (tester) async {
      final api = _CycleApi()
        ..alerts = const PartnerAlertPreference(
          pillEnabled: true,
          pillRepeatEnabled: true,
          pillRepeatMinutes: 20,
        );
      await tester.pumpWidget(_app(
        brightness,
        PartnerAlertsScreen(
          api: api,
          strings: _en,
          share: const ShareState(status: 'active', ownerName: 'Her'),
          reschedule: (_) async => LocalReminderSyncStatus.scheduled,
        ),
      ));
      await tester.pumpAndSettle();

      final minutesField =
          find.byKey(const ValueKey('pill-repeat-minutes-field'));
      expect(tester.widget<TextField>(minutesField).controller!.text, '20');

      api.saveError = Exception('boom');
      await tester.enterText(minutesField, '45');
      // The debounce has not fired yet: nothing has been saved or optimistically
      // applied, so the helper still reflects the saved value.
      expect(find.text(_en.pillRepeatHelper(20)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(api.saves.last.pillRepeatMinutes, 45);
      expect(
        tester.widget<TextField>(minutesField).controller!.text,
        '20',
        reason: 'failed save must roll the field back to the saved value',
      );
      expect(find.text(_en.pillRepeatHelper(20)), findsOneWidget);
      expect(find.text(_en.pillRepeatRangeError), findsNothing);
      expect(find.text(_en.connectionError), findsOneWidget);
    });

    testWidgets(
        'partner alerts keep saved toggles and cancel schedules when calendar consent blocks data ($brightness)',
        (tester) async {
      final api = _CycleApi(
        cycleError: ApiException(
          'get cycle',
          http.Response(
            '{"error":"calendar owner consent required"}',
            403,
          ),
        ),
      )..alerts = const PartnerAlertPreference(pmsEnabled: true);
      final scheduled = <List<PlannedAlert>>[];
      var cancellations = 0;

      await tester.pumpWidget(_app(
        brightness,
        PartnerAlertsScreen(
          api: api,
          strings: _en,
          share: const ShareState(status: 'active', ownerName: 'Her'),
          partnerAlertScheduler: (alerts) async {
            scheduled.add(alerts);
            return LocalReminderSyncStatus.scheduled;
          },
          cancelPartnerAlerts: () async {
            cancellations++;
            return LocalReminderSyncStatus.cancelled;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(cancellations, 1);
      expect(scheduled, isEmpty);
      expect(
        tester
            .widget<Switch>(find.descendant(
              of: find.byKey(const ValueKey('alert-pms')),
              matching: find.byType(Switch),
            ))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(find.descendant(
              of: find.byKey(const ValueKey('alert-pill')),
              matching: find.byType(Switch),
            ).first)
            .value,
        isFalse,
      );
      expect(find.text(_en.sharedCalendarOwnerConsentRequired), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('alert-pill')),
        matching: find.byType(Switch),
      ).first);
      await tester.pumpAndSettle();

      expect(api.saves.last.pmsEnabled, isTrue);
      expect(api.saves.last.pillEnabled, isTrue);
      expect(cancellations, 2);
      expect(scheduled, isEmpty);
    });

    testWidgets('consent block cancels a partner plan while preference loads',
        (tester) async {
      final firstCycle = Completer<CycleInfo>()
        ..complete(_cycleAround(DateTime.now()));
      final blockedCycle = Completer<CycleInfo>();
      final api = _CycleApi()
        ..cycleRequests.addAll([firstCycle, blockedCycle])
        ..alertCompleter = Completer<PartnerAlertPreference>();
      final cycleRefresh = ValueNotifier<int>(0);
      addTearDown(cycleRefresh.dispose);
      final scheduled = <List<PlannedAlert>>[];

      await tester.pumpWidget(_app(
        brightness,
        CalendarScreen(
          api: api,
          user: const User(
            id: 'partner',
            email: 'p@example.invalid',
            name: 'P',
            role: 'partner',
          ),
          strings: _en,
          onOpenSettings: () {},
          share: const ShareState(status: 'active', ownerName: 'Her'),
          cycleRefreshSignal: cycleRefresh,
          partnerAlertScheduler: (alerts) async {
            scheduled.add(alerts);
            return LocalReminderSyncStatus.cancelled;
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(api.cycleCalls, 1);

      cycleRefresh.value++;
      blockedCycle.completeError(ApiException(
        'get cycle',
        http.Response(
          '{"error":"calendar owner consent required"}',
          403,
        ),
      ));
      await tester.pumpAndSettle();
      expect(scheduled, hasLength(1));
      expect(scheduled.single, isEmpty);

      api.alertCompleter!.complete(
        const PartnerAlertPreference(pmsEnabled: true, pillEnabled: true),
      );
      await tester.pumpAndSettle();
      expect(scheduled, hasLength(1));
      expect(scheduled.single, isEmpty);
    });

    testWidgets(
        'partner alerts explain suppressed PMS only for menopause ($brightness)',
        (tester) async {
      await tester.pumpWidget(_app(
          brightness,
          PartnerAlertsScreen(
            key: const ValueKey('menopause-alerts'),
            api: _CycleApi(
                cycle: const CycleInfo(note: 'pms_suppressed_menopause')),
            strings: _en,
            share: const ShareState(status: 'active', ownerName: 'Her'),
            reschedule: (_) async => LocalReminderSyncStatus.scheduled,
          )));
      await tester.pumpAndSettle();
      expect(find.text(_en.pmsNotCounted), findsOneWidget);

      await tester.pumpWidget(_app(
          brightness,
          PartnerAlertsScreen(
            key: const ValueKey('perimenopause-alerts'),
            api: _CycleApi(
                cycle: const CycleInfo(note: 'pms_counted_perimenopause')),
            strings: _en,
            share: const ShareState(status: 'active', ownerName: 'Her'),
            reschedule: (_) async => LocalReminderSyncStatus.scheduled,
          )));
      await tester.pumpAndSettle();
      expect(find.text(_en.pmsNotCounted), findsNothing);
    });

    testWidgets(
        'partner alert controls render while cycle is still loading ($brightness)',
        (tester) async {
      final api = _CycleApi()..cycleCompleter = Completer<CycleInfo>();
      await tester.pumpWidget(_app(
          brightness,
          PartnerAlertsScreen(
            api: api,
            strings: _en,
            share: const ShareState(status: 'active', ownerName: 'Her'),
            reschedule: (_) async => LocalReminderSyncStatus.scheduled,
          )));
      await tester.pumpAndSettle();
      expect(api.cycleCalls, 1);
      expect(find.byKey(const ValueKey('alert-pms')), findsOneWidget);
      expect(find.byKey(const ValueKey('alert-pill')), findsOneWidget);
      expect(find.text(_en.pmsNotCounted), findsNothing);

      api.cycleCompleter!
          .complete(const CycleInfo(note: 'pms_suppressed_menopause'));
      await tester.pumpAndSettle();
      expect(find.text(_en.pmsNotCounted), findsOneWidget);
    });

    testWidgets(
        'settings: partner gets Alerts, owner can switch role '
        '($brightness)', (tester) async {
      Future<void> pumpSettings(User user, ShareState share) async {
        await tester.pumpWidget(_app(
          brightness,
          SettingsPage(
            api: _CycleApi(),
            strings: _en,
            language: AppLanguage.en,
            themeMode: ThemeMode.system,
            palette: AppPalette.blue,
            onLanguageChanged: (_) {},
            onThemeModeChanged: (_) {},
            onPaletteChanged: (_) {},
            onApiBaseChanged: () {},
            user: user,
            share: share,
            onShareChanged: (_) {},
            onLogout: () async {},
            onRoleChanged: (_) {},
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpSettings(
        const User(id: 'p', email: 'p@b.c', name: 'P', role: 'partner'),
        const ShareState(status: 'active', canEditCalendar: false),
      );
      expect(find.byKey(const ValueKey('settings-partner-alerts')),
          findsOneWidget);
      expect(find.text('Reminder'), findsNothing);
      expect(find.text('Create invite'), findsNothing);

      await pumpSettings(
        const User(id: 'o', email: 'o@b.c', name: 'O', role: 'owner'),
        const ShareState(status: 'none'),
      );
      expect(find.text('Reminder'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-switch-partner')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('settings-switch-partner')),
          findsOneWidget);

      await pumpSettings(
        const User(id: 'o', email: 'o@b.c', name: 'O', role: 'owner'),
        const ShareState(status: 'active', partnerName: 'Bf'),
      );
      expect(
          find.byKey(const ValueKey('settings-switch-partner')), findsNothing);
    });
  }
}
