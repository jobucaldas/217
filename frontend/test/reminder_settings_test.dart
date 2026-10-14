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

  @override
  Future<ReminderPreference?> getReminderPreference() async => pref;

  @override
  Future<ReminderPreference> upsertReminderPreference({
    required bool enabled,
    required String time,
    required String timezone,
  }) async {
    if (saveError != null) throw saveError!;
    pref = ReminderPreference(
      enabled: enabled,
      time: time,
      timezone: timezone,
      deliverable: false,
    );
    return pref;
  }

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
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
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
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(operations, isEmpty);
    expect(queue.revision, 2);
  });
}
