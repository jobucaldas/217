import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _CalendarApi extends ApiClient {
  _CalendarApi() : super(AppConfig.fromEnvironment());

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required bool show,
  required VoidCallback onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildApp217Theme(brightness: brightness),
      home: CalendarScreen(
        api: _CalendarApi(),
        user: const User(id: 'u', email: 'a@b.c', name: 'A'),
        strings: const Strings(AppLanguage.en),
        onOpenSettings: () {},
        showReminderHint: show,
        onDismissReminderHint: onDismiss,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const hint = 'Set a daily reminder in Settings > Reminder.';

  for (final brightness in Brightness.values) {
    testWidgets(
        'calendar reminder hint is readable and dismissable ($brightness)',
        (tester) async {
      var dismissed = 0;
      await _pump(
        tester,
        brightness: brightness,
        show: true,
        onDismiss: () => dismissed++,
      );
      final scheme =
          buildApp217ColorScheme(brightness, palette: AppPalette.blue);
      final body = find.text(hint);
      expect(body, findsOneWidget);
      expect(
        tester.widget<Text>(body).style?.color,
        scheme.onSecondaryContainer,
      );
      await tester.tap(find.byKey(const ValueKey('reminder-hint-dismiss')));
      expect(dismissed, 1);
    });
  }

  testWidgets('reminder hint closes itself after ten seconds', (tester) async {
    var dismissed = 0;
    await _pump(
      tester,
      brightness: Brightness.light,
      show: true,
      onDismiss: () => dismissed++,
    );
    await tester.pump(const Duration(seconds: 9));
    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(dismissed, 1);
  });

  testWidgets('no reminder hint unless asked', (tester) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      show: false,
      onDismiss: () {},
    );
    expect(find.text(hint), findsNothing);
  });
}
