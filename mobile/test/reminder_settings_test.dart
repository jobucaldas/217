import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
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

  @override
  Future<ReminderPreference?> getReminderPreference() async => pref;

  @override
  Future<ReminderPreference> upsertReminderPreference({
    required bool enabled,
    required String time,
    required String timezone,
  }) async {
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
  final strings = Strings(false);
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
          expect(find.textContaining('Android:'), findsOneWidget);
          expect(find.text('Save'), findsOneWidget);
        },
      );
    }
  }
}
