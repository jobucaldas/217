import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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
  _CycleApi({this.entries = const [], CycleInfo? cycle})
      : cycle = cycle ?? CycleInfo.empty,
        super(AppConfig.fromEnvironment());

  final List<Entry> entries;
  final CycleInfo cycle;
  String? role;
  PartnerAlertPreference alerts = const PartnerAlertPreference();
  final saves = <PartnerAlertPreference>[];

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;

  @override
  Future<CycleInfo> getCycle(String today) async => cycle;

  @override
  Future<PartnerAlertPreference> getPartnerAlerts() async => alerts;

  @override
  Future<PartnerAlertPreference> savePartnerAlerts(
    PartnerAlertPreference pref,
  ) async {
    saves.add(pref);
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
    List<PlannedAlert> plan(PartnerAlertPreference pref, {bool logged = false}) =>
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

      final scheme = Theme.of(tester.element(find.text('I take the pill')))
          .colorScheme;
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
      expect(find.text('You are not invited to her 217 calendar'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('switch-to-owner')));
      expect(switched, isTrue);
    });

    testWidgets('calendar draws PMS ring, period drops and cycle line '
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
        entries: [Entry(date: key(yesterday), taken: true, notes: '', period: true)],
      );
      await tester.pumpWidget(_app(
        brightness,
        CalendarScreen(
          api: api,
          user: const User(id: 'u2', email: 'bf@b.c', name: 'Bf', role: 'partner'),
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
        find.descendant(of: line, matching: find.textContaining('PMS likely now')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('pms-${today.month}-${today.day}')),
          findsWidgets);
      final inPeriod = _d(today, 4);
      expect(
        find.byKey(ValueKey('predicted-period-${inPeriod.month}-${inPeriod.day}')),
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

    testWidgets('owner without period history gets the marking hint '
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
      expect(find.text('Mark period days to see PMS predictions'), findsOneWidget);
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
      final notes = find.byTooltip('Add note');
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

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('alert-pill')),
        matching: find.byType(Switch),
      ));
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

      final scheme = Theme.of(tester.element(find.text('PMS heads-up')))
          .colorScheme;
      final time = tester.widget<Text>(find.text('09:00'));
      expect(meetsBodyContrast(time.style!.color!, scheme.surface), isTrue);
    });

    testWidgets('settings: partner gets Alerts, owner can switch role '
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
      expect(find.byKey(const ValueKey('settings-partner-alerts')), findsOneWidget);
      expect(find.text('Reminder'), findsNothing);
      expect(find.text('Create invite'), findsNothing);

      await pumpSettings(
        const User(id: 'o', email: 'o@b.c', name: 'O', role: 'owner'),
        const ShareState(status: 'none'),
      );
      expect(find.text('Reminder'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-switch-partner')), findsOneWidget);

      await pumpSettings(
        const User(id: 'o', email: 'o@b.c', name: 'O', role: 'owner'),
        const ShareState(status: 'active', partnerName: 'Bf'),
      );
      expect(find.byKey(const ValueKey('settings-switch-partner')), findsNothing);
    });
  }
}
