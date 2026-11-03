import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api() : super(AppConfig.fromEnvironment());

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];

  @override
  Future<CycleInfo> getCycle(String today) async => CycleInfo.empty;
}

const _jump = ValueKey('jump-to-today-button');

Future<List<Object>> _layout(WidgetTester tester) async {
  final cells = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_DayCell',
  );
  final size = tester.view.physicalSize;
  final visible = cells
      .evaluate()
      .map((e) => tester.getRect(find.byWidget(e.widget)))
      .where((r) => r.left >= 0 && r.right <= size.width)
      .toList();
  return [
    visible.map((r) => r.top).reduce((a, b) => a < b ? a : b),
    visible.first.size,
    tester.getTopLeft(find.byTooltip('Next month')),
    tester.getTopLeft(find.byTooltip('Previous month')),
    tester.getSize(find.byKey(const ValueKey('day-summary'))),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [
    Size(1920, 1080),
    Size(1600, 1000),
    Size(400, 850),
  ]) {
    for (final partner in [false, true]) {
      testWidgets(
          'jump to today keeps the layout and height at $size '
          '(${partner ? 'partner' : 'owner'})', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildApp217Theme(
            brightness: Brightness.dark,
            palette: AppPalette.blue,
          ).copyWith(
            // What web and desktop use by default.
            visualDensity: VisualDensity.compact,
          ),
          home: CalendarScreen(
            api: _Api(),
            user: User(
              id: 'u',
              email: 'u@example.invalid',
              name: 'U',
              role: partner ? 'partner' : 'owner',
            ),
            share: partner
                ? const ShareState(
                    status: 'active',
                    ownerName: 'O',
                    canEditCalendar: false,
                  )
                : const ShareState(status: 'none'),
            strings: const Strings(AppLanguage.en),
            onOpenSettings: () {},
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(_jump), findsNothing);
        final home = await _layout(tester);

        // Selecting another day of the same month shows the button too.
        final other = DateTime.now().day == 15 ? '16' : '15';
        final now = DateTime.now();
        await tester.tap(find.descendant(
          of: find.byKey(ValueKey('${now.year}-${now.month}')),
          matching: find.text(other),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(_jump), findsOneWidget);
        // The summary's own height follows the day shown (tags), not the button.
        expect((await _layout(tester)).sublist(0, 4), home.sublist(0, 4));

        // Whichever action the day has: future days are only viewed.
        final action = find.byWidgetPredicate((w) =>
            w.key == const ValueKey('view-day-button') ||
            w.key == const ValueKey('update-day-button'));
        expect(tester.getSize(find.byKey(_jump)).height,
            tester.getSize(action).height);

        // Another month too: the header and arrows stay where they were.
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(find.byKey(_jump), findsOneWidget);
        final away = await _layout(tester);
        expect(away[2], home[2]);
        expect(away[3], home[3]);
        // The summary's own height follows the day shown, not the button.
        if (size.width >= 560) expect(away, home);

        await tester.tap(find.byKey(_jump));
        await tester.pumpAndSettle();
        expect(find.byKey(_jump), findsNothing);
        expect(await _layout(tester), home);
      });
    }
  }
}
