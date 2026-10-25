import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/screens/partner_alerts_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

const _en = Strings(AppLanguage.en);

/// Plans alerts for the given preference and cycle.
List<PlannedAlert> _plan({
  required DateTime now,
  required PartnerAlertPreference pref,
  CycleInfo cycle = CycleInfo.empty,
  bool todayLogged = false,
}) =>
    planPartnerAlerts(
      now: now,
      pref: pref,
      cycle: cycle,
      todayLogged: todayLogged,
      pmsTitle: (_) => 'pms',
      pmsBody: (_) => 'pms',
      pillTitle: 'pill',
      pillBody: 'pill body',
    );

List<PlannedAlert> _onDay(List<PlannedAlert> alerts, DateTime day) => alerts
    .where((a) =>
        a.when.year == day.year &&
        a.when.month == day.month &&
        a.when.day == day.day)
    .toList();

List<PlannedAlert> _repeats(List<PlannedAlert> alerts) =>
    alerts.where((a) => a.id >= partnerPillRepeatIdBase).toList();

class _RepeatApi extends ApiClient {
  _RepeatApi() : super(AppConfig.fromEnvironment());

  PartnerAlertPreference alerts = const PartnerAlertPreference(
    pillEnabled: true,
  );
  final saves = <PartnerAlertPreference>[];

  @override
  Future<CycleInfo> getCycle(String today) async => CycleInfo.empty;

  @override
  Future<PartnerAlertPreference> getPartnerAlerts() async => alerts;

  @override
  Future<PartnerAlertPreference> savePartnerAlerts(
    PartnerAlertPreference pref,
  ) async {
    saves.add(pref);
    return alerts = pref;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _RepeatApi api,
  List<PartnerAlertPreference> scheduled,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(
        brightness: Brightness.light, palette: AppPalette.blue),
    home: PartnerAlertsScreen(
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
}

Finder _repeatSwitch() => find.descendant(
      of: find.byKey(const ValueKey('alert-pill-repeat')),
      matching: find.byType(Switch),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final now = DateTime(2026, 10, 3, 12);
  final today = DateTime(2026, 10, 3);
  final tomorrow = DateTime(2026, 10, 4);

  group('pill repeat planning', () {
    test('off means no repeats at all', () {
      final alerts = _plan(
        now: now,
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
        ),
      );
      expect(_repeats(alerts), isEmpty);
      expect(alerts.length, pillAlertHorizonDays);
    });

    test('out-of-range intervals are treated as off', () {
      for (final bad in [-5, 0, 121]) {
        final alerts = _plan(
          now: now,
          pref: PartnerAlertPreference(
            pillEnabled: true,
            pillTime: '21:00',
            pillRepeatMinutes: bad,
          ),
        );
        expect(_repeats(alerts), isEmpty, reason: 'interval $bad');
      }
    });

    test('repeats follow the pill time every N minutes until 23:59', () {
      final alerts = _plan(
        now: now,
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatMinutes: 30,
        ),
      );
      final todays = _onDay(_repeats(alerts), today).map((a) => a.when);
      expect(todays, [
        DateTime(2026, 10, 3, 21, 30),
        DateTime(2026, 10, 3, 22),
        DateTime(2026, 10, 3, 22, 30),
        DateTime(2026, 10, 3, 23),
        DateTime(2026, 10, 3, 23, 30),
      ]);
      // Tomorrow repeats use the same grid.
      expect(_onDay(_repeats(alerts), tomorrow).first.when,
          DateTime(2026, 10, 4, 21, 30));
    });

    test('last repeat stays before 23:59 and nothing crosses midnight', () {
      final alerts = _plan(
        now: now,
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '22:00',
          pillRepeatMinutes: 15,
        ),
      );
      final todays =
          _onDay(_repeats(alerts), today).map((a) => a.when).toList();
      expect(todays.last, DateTime(2026, 10, 3, 23, 45));
      expect(todays.every((w) => w.isBefore(DateTime(2026, 10, 3, 23, 59))),
          isTrue);
      expect(_repeats(alerts).every((a) => a.when.day <= 4), isTrue);
    });

    test('per-day cap limits dense intervals to 48 repeats', () {
      final alerts = _plan(
        now: now,
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '09:00',
          pillRepeatMinutes: 1,
        ),
      );
      final todays = _onDay(_repeats(alerts), today).toList();
      final tomorrows = _onDay(_repeats(alerts), tomorrow).toList();
      expect(todays.length, pillRepeatMaxPerDay);
      expect(tomorrows.length, pillRepeatMaxPerDay);
      expect(todays.first.when, DateTime(2026, 10, 3, 12, 1));
      expect(todays.last.when, DateTime(2026, 10, 3, 12, 48));
    });

    test('a pill time already past starts repeats on the next grid point', () {
      final alerts = _plan(
        now: DateTime(2026, 10, 3, 21, 40),
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatMinutes: 15,
        ),
      );
      final todays = _onDay(_repeats(alerts), today).map((a) => a.when);
      expect(todays.first, DateTime(2026, 10, 3, 21, 45));
      // The base alert for today was already in the past.
      expect(alerts.where((a) => a.id == partnerPillIdBase), isEmpty);
    });

    test('logged today skips today repeats but keeps tomorrow', () {
      final alerts = _plan(
        now: now,
        todayLogged: true,
        pref: const PartnerAlertPreference(
          pillEnabled: true,
          pillTime: '21:00',
          pillRepeatMinutes: 30,
        ),
      );
      expect(_onDay(_repeats(alerts), today), isEmpty);
      expect(_onDay(_repeats(alerts), tomorrow), hasLength(5));
    });

    test('repeat ids are unique, in their reserved range and never collide',
        () {
      final cycle = CycleInfo(predictions: [
        for (var i = 0; i < 10; i++)
          CycleWindow(
            periodStart: DateTime(2026, 10, 10 + i * 28),
            periodEnd: DateTime(2026, 10, 14 + i * 28),
            pmsStart: DateTime(2026, 10, 7 + i * 28),
            pmsEnd: DateTime(2026, 10, 9 + i * 28),
          ),
      ]);
      final alerts = _plan(
        now: now,
        cycle: cycle,
        pref: const PartnerAlertPreference(
          pmsEnabled: true,
          pillEnabled: true,
          pillTime: '09:00',
          pillRepeatMinutes: 1,
        ),
      );
      final ids = alerts.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      final repeatIds = _repeats(alerts).map((a) => a.id).toList();
      expect(repeatIds, isNotEmpty);
      expect(
          repeatIds.every((id) =>
              id >= partnerPillRepeatIdBase &&
              id < partnerPillRepeatIdBase + partnerPillRepeatIdCount),
          isTrue);
      expect(
        ids.where(
            (id) => id >= partnerPmsIdBase && id < partnerPillRepeatIdBase),
        everyElement(isNot(anyOf(
          greaterThanOrEqualTo(partnerPillRepeatIdBase),
          lessThan(partnerPmsIdBase),
        ))),
      );
      // Two days of repeats fit the reserved block with room to spare.
      expect(repeatIds.length,
          lessThanOrEqualTo(pillRepeatDays * pillRepeatMaxPerDay));
      expect(pillRepeatDays * pillRepeatMaxPerDay,
          lessThanOrEqualTo(partnerPillRepeatIdCount));
      // Whole plan stays far under Android's pending-alarm limit (~500).
      expect(alerts.length, lessThan(200));
    });
  });

  group('PartnerAlertPreference JSON', () {
    test('round-trips the repeat interval', () {
      const pref = PartnerAlertPreference(
        pillEnabled: true,
        pillTime: '20:30',
        pillRepeatMinutes: 45,
      );
      final json = pref.toJson();
      expect(json['pill_repeat_minutes'], 45);
      final back = PartnerAlertPreference.fromJson(json);
      expect(back.pillRepeatMinutes, 45);
      expect(back.pillRepeatOn, isTrue);
      expect(back.pillTime, '20:30');
    });

    test('a missing field from an older server means off', () {
      final pref = PartnerAlertPreference.fromJson({
        'pms_enabled': false,
        'pms_time': '09:00',
        'pill_enabled': true,
        'pill_time': '21:00',
      });
      expect(pref.pillRepeatMinutes, pillRepeatOff);
      expect(pref.pillRepeatOn, isFalse);
    });

    test('copyWith changes only the repeat interval', () {
      const base = PartnerAlertPreference(pillEnabled: true);
      final next = base.copyWith(pillRepeatMinutes: 10);
      expect(next.pillRepeatMinutes, 10);
      expect(next.pillEnabled, isTrue);
      expect(next.copyWith(pillRepeatMinutes: pillRepeatOff).pillRepeatOn,
          isFalse);
    });
  });

  testWidgets('repeat is off by default and only enabled with the pill toggle',
      (tester) async {
    final api = _RepeatApi()..alerts = const PartnerAlertPreference();
    final scheduled = <PartnerAlertPreference>[];
    await _pump(tester, api, scheduled);

    expect(tester.widget<Switch>(_repeatSwitch()).value, isFalse);
    expect(tester.widget<Switch>(_repeatSwitch()).onChanged, isNull);
    expect(
        find.byKey(const ValueKey('alert-pill-repeat-interval')), findsNothing);
  });

  testWidgets('turning repeat on saves a default and the interval can change',
      (tester) async {
    final api = _RepeatApi();
    final scheduled = <PartnerAlertPreference>[];
    await _pump(tester, api, scheduled);

    await tester.tap(_repeatSwitch());
    await tester.pumpAndSettle();
    expect(api.saves.last.pillRepeatMinutes, pillRepeatDefaultMinutes);
    expect(find.text(_en.pillRepeatEvery(pillRepeatDefaultMinutes)),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('alert-pill-repeat-interval')));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, '15');

    // Letters are dropped and a fourth digit is refused, so the field keeps
    // its last valid text.
    await tester.enterText(field, '1a1b5');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '115');
    await tester.enterText(field, '1000');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '115');
    expect(find.text(_en.pillRepeatIntervalInvalid), findsNothing);

    for (final bad in ['0', '121']) {
      await tester.enterText(field, bad);
      await tester.pumpAndSettle();
      expect(find.text(_en.pillRepeatIntervalInvalid), findsOneWidget,
          reason: 'value $bad');
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNull, reason: 'value $bad');
    }

    await tester.tap(find.widgetWithText(ChoiceChip, '30'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '30');
    await tester.tap(find.widgetWithText(FilledButton, _en.save));
    await tester.pumpAndSettle();

    expect(api.saves.last.pillRepeatMinutes, 30);
    expect(api.saves.last.pillEnabled, isTrue);
    expect(find.text(_en.pillRepeatEvery(30)), findsOneWidget);
    expect(scheduled.last.pillRepeatMinutes, 30);
  });

  testWidgets('custom minutes save from the text field', (tester) async {
    final api = _RepeatApi()
      ..alerts = const PartnerAlertPreference(
        pillEnabled: true,
        pillRepeatMinutes: 15,
      );
    final scheduled = <PartnerAlertPreference>[];
    await _pump(tester, api, scheduled);

    await tester.tap(find.byKey(const ValueKey('alert-pill-repeat-interval')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '45');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, _en.save));
    await tester.pumpAndSettle();

    expect(api.saves.last.pillRepeatMinutes, 45);
    expect(find.text(_en.pillRepeatEvery(45)), findsOneWidget);
  });

  testWidgets('turning the pill toggle off disables the repeat controls',
      (tester) async {
    final api = _RepeatApi()
      ..alerts = const PartnerAlertPreference(
        pillEnabled: true,
        pillRepeatMinutes: 15,
      );
    final scheduled = <PartnerAlertPreference>[];
    await _pump(tester, api, scheduled);

    final pillSwitch = find
        .descendant(
          of: find.byKey(const ValueKey('alert-pill')),
          matching: find.byType(Switch),
        )
        .first;
    await tester.tap(pillSwitch);
    await tester.pumpAndSettle();
    expect(api.saves.last.pillEnabled, isFalse);
    expect(tester.widget<Switch>(_repeatSwitch()).onChanged, isNull);
    final interval = tester.widget<ListTile>(
        find.byKey(const ValueKey('alert-pill-repeat-interval')));
    expect(interval.enabled, isFalse);
  });
}
