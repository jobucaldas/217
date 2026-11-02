import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _EmptyApi extends ApiClient {
  _EmptyApi() : super(AppConfig.fromEnvironment());

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];

  @override
  Future<CycleInfo> getCycle(String today) async => CycleInfo.empty;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(
      brightness: Brightness.dark,
      palette: AppPalette.blue,
    ),
    home: CalendarScreen(
      api: _EmptyApi(),
      user: const User(id: 'u1', email: 'o@example.invalid', name: 'O'),
      strings: const Strings(AppLanguage.en),
      onOpenSettings: () {},
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _todayCell() {
  final now = DateTime.now();
  return find.descendant(
    of: find.byKey(ValueKey('${now.year}-${now.month}')),
    matching: find.text('${now.day}'),
  );
}

final _jump = find.byKey(const ValueKey('jump-to-today-button'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a single tap selects without opening the editor',
      (tester) async {
    await _pump(tester);
    await tester.tap(_todayCell());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsNothing);

    // Two slow taps are two selections, not a double tap.
    await tester.tap(_todayCell());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsNothing);
  });

  testWidgets('a double tap opens the editor', (tester) async {
    await _pump(tester);
    await tester.tap(_todayCell());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_todayCell());
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);
  });

  testWidgets('the update-day button opens the editor', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('update-day-button')));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorSheet), findsOneWidget);
  });

  testWidgets('jump to today shows away from today and brings you back',
      (tester) async {
    await _pump(tester);
    expect(_jump, findsNothing);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(_jump, findsOneWidget);

    await tester.tap(_jump);
    await tester.pumpAndSettle();
    expect(_jump, findsNothing);
    expect(_todayCell(), findsOneWidget);
    expect(find.byType(DayEditorSheet), findsNothing);
  });

  testWidgets('jump to today scrolls through every month within a second',
      (tester) async {
    await _pump(tester);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
    }

    final now = DateTime.now();
    final expected = {
      for (var i = 0; i <= 6; i++)
        '${DateTime(now.year, now.month - i).year}-'
            '${DateTime(now.year, now.month - i).month}',
    };
    final seen = <String>{};
    await tester.tap(_jump);
    for (var t = 0; t < 1000; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final key in expected) {
        if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) seen.add(key);
      }
    }
    expect(seen, expected);
    // Done within the second: nothing left to animate.
    expect(tester.hasRunningAnimations, isFalse);
    expect(_jump, findsNothing);
    expect(_todayCell(), findsOneWidget);
  });
}
