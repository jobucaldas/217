import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/daily_reminder_sync_queue.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/screens/reminder_settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _FakeReminderApi extends ApiClient {
  _FakeReminderApi() : super(AppConfig.fromEnvironment());

  ReminderPreference pref = const ReminderPreference(
    enabled: false,
    time: '09:00',
    timezone: 'UTC',
    deliverable: false,
  );
  Object? saveError;
  Duration saveDelay = Duration.zero;
  final List<ReminderPreference> saves = [];
  List<Entry> entries = [];

  @override
  Future<ReminderPreference?> getReminderPreference() async => pref;

  @override
  Future<ReminderPreference> upsertReminderPreference({
    required bool enabled,
    required String time,
    required String timezone,
    bool repeatEnabled = false,
    int repeatMinutes = 15,
  }) async {
    final attempted = ReminderPreference(
      enabled: enabled,
      time: time,
      timezone: timezone,
      deliverable: false,
      repeatEnabled: repeatEnabled,
      repeatMinutes: repeatMinutes,
    );
    saves.add(attempted);
    if (saveDelay > Duration.zero) await Future<void>.delayed(saveDelay);
    if (saveError != null) throw saveError!;
    pref = attempted;
    return pref;
  }

  @override
  Future<List<Entry>> listEntries(int year, int month) async => entries;

  @override
  Future<({bool configured, String publicKey})> vapidConfig() async =>
      (configured: false, publicKey: '');
}

Future<void> _pumpReminder(
  WidgetTester tester, {
  required Brightness brightness,
  required AppPalette palette,
}) async {
  final strings = Strings(AppLanguage.en);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildApp217Theme(brightness: brightness, palette: palette),
      home: ReminderSettingsScreen(
        api: _FakeReminderApi(),
        strings: strings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final palette in AppPalette.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'reminder settings loads in ${palette.name}/$brightness',
        (tester) async {
          await _pumpReminder(
            tester,
            brightness: brightness,
            palette: palette,
          );
          expect(find.text('Remind me daily'), findsOneWidget);
          expect(find.textContaining('On Android'), findsOneWidget);
          expect(find.text('Save'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('switching reminders reports the new state', (tester) async {
    // The Android plugin has no host in tests; use the server-only path.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final toggled = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(
          api: _FakeReminderApi(),
          strings: const Strings(AppLanguage.en),
          onToggled: toggled.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final enableSwitch = find.descendant(
      of: find.byKey(const ValueKey('reminder-enable-toggle')),
      matching: find.byType(Switch),
    );
    await tester.tap(enableSwitch);
    await tester.pumpAndSettle();
    await tester.tap(enableSwitch);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(toggled, [true, false]);
  });

  testWidgets('403 while saving does not schedule locally', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final api = _FakeReminderApi()
      ..saveError = ApiException(
        'save reminder',
        http.Response('{"consent_version":2}', 403),
      );
    final operations = <bool>[];
    final queue = DailyReminderSyncQueue(({
      required enabled,
      required timeHhMm,
      required title,
      required body,
      repeatEnabled = false,
      repeatMinutes = 15,
      todayLogged = false,
    }) async {
      operations.add(enabled);
      return LocalReminderSyncResult(
        enabled
            ? LocalReminderSyncStatus.scheduled
            : LocalReminderSyncStatus.cancelled,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(
          api: api,
          strings: const Strings(AppLanguage.en),
          dailyReminderSyncQueue: queue,
        ),
      ),
    );
    await tester.pumpAndSettle();
    operations.clear();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('reminder-enable-toggle')),
      matching: find.byType(Switch),
    ));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(operations, isEmpty);
    expect(queue.revision, 2);
  });

  group('repeat', () {
    final toggleKey = find.byKey(const ValueKey('reminder-repeat-toggle'));
    final minutesField =
        find.byKey(const ValueKey('reminder-repeat-minutes-field'));
    const strings = Strings(AppLanguage.en);

    testWidgets('hidden until the daily reminder itself is on',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(
          api: _FakeReminderApi(),
          strings: strings,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.descendant(
          of: toggleKey,
          matching: find.byType(Switch),
        )).onChanged,
        isNull,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('toggling shows the field, validates, saves', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final api = _FakeReminderApi()
        ..pref = const ReminderPreference(
          enabled: true,
          time: '09:00',
          timezone: 'UTC',
          deliverable: false,
        );
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(api: api, strings: strings),
      ));
      await tester.pumpAndSettle();

      expect(toggleKey, findsOneWidget);
      expect(minutesField, findsNothing);

      await tester.tap(find.descendant(
        of: toggleKey,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(api.saves.last.repeatEnabled, isTrue);
      expect(api.saves.last.repeatMinutes, 15);
      expect(minutesField, findsOneWidget);
      expect(find.text(strings.pillRepeatRangeError), findsNothing);
      expect(find.text(strings.reminderRepeatHelper(15)), findsOneWidget);

      for (final invalid in ['0', '121', '']) {
        final savesBefore = api.saves.length;
        await tester.enterText(minutesField, invalid);
        await tester.pumpAndSettle();
        expect(find.text(strings.pillRepeatRangeError), findsOneWidget);
        expect(find.text(strings.reminderRepeatHelper(15)), findsNothing);
        expect(api.saves.length, savesBefore, reason: 'invalid: $invalid');
      }

      await tester.enterText(minutesField, '45');
      await tester.pump();
      // Saving the typed minutes is debounced; nothing is sent yet.
      expect(find.text(strings.pillRepeatRangeError), findsNothing);
      expect(api.saves.last.repeatMinutes, 15);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text(strings.pillRepeatRangeError), findsNothing);
      expect(find.text(strings.reminderRepeatHelper(45)), findsOneWidget);
      expect(api.saves.last.repeatMinutes, 45);
      expect(api.saves.last.repeatEnabled, isTrue);

      await tester.tap(find.descendant(
        of: toggleKey,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(api.saves.last.repeatEnabled, isFalse);
      expect(minutesField, findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'digits typed quickly debounce to a single save and the field '
        'stays editable while a save is in flight', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final api = _FakeReminderApi()
        ..pref = const ReminderPreference(
          enabled: true,
          time: '09:00',
          timezone: 'UTC',
          deliverable: false,
        )
        ..saveDelay = const Duration(seconds: 2);
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(api: api, strings: strings),
      ));
      await tester.pumpAndSettle();

      // Enabling the toggle kicks off a slow save (still in flight below).
      await tester.tap(find.descendant(
        of: toggleKey,
        matching: find.byType(Switch),
      ));
      await tester.pump();
      expect(minutesField, findsOneWidget);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      await tester.enterText(minutesField, '4');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);
      expect(api.saves.any((p) => p.repeatMinutes == 45), isFalse);

      await tester.enterText(minutesField, '45');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);
      expect(api.saves.any((p) => p.repeatMinutes == 45), isFalse);

      await tester.pump(const Duration(milliseconds: 600));
      expect(api.saves.any((p) => p.repeatMinutes == 45), isFalse);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      await tester.pump(const Duration(seconds: 2));
      expect(api.saves.where((p) => p.repeatMinutes == 45).length, 1);
      expect(tester.widget<TextField>(minutesField).enabled, isTrue);

      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a failed save restores the previous value', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final api = _FakeReminderApi()
        ..pref = const ReminderPreference(
          enabled: true,
          time: '09:00',
          timezone: 'UTC',
          deliverable: false,
          repeatEnabled: true,
          repeatMinutes: 20,
        );
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(api: api, strings: strings),
      ));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(minutesField).controller!.text, '20');

      api.saveError = Exception('boom');
      await tester.enterText(minutesField, '45');
      expect(find.text(strings.reminderRepeatHelper(20)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(minutesField).controller!.text, '20');
      expect(find.text(strings.reminderRepeatHelper(20)), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'a failed save does not clobber a newer unflushed edit, which still '
        'saves afterwards', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final api = _FakeReminderApi()
        ..pref = const ReminderPreference(
          enabled: true,
          time: '09:00',
          timezone: 'UTC',
          deliverable: false,
          repeatEnabled: true,
          repeatMinutes: 20,
        );
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: ReminderSettingsScreen(api: api, strings: strings),
      ));
      await tester.pumpAndSettle();

      api.saveError = Exception('boom');
      await tester.enterText(minutesField, '45');
      await tester.pump(const Duration(milliseconds: 700));
      // A newer edit lands before the failed save's catch block runs.
      await tester.enterText(minutesField, '60');
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(minutesField).controller!.text, '60');

      api.saveError = null;
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(api.saves.last.repeatMinutes, 60);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
