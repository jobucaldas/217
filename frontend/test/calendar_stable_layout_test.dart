import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _Api extends ApiClient {
  _Api(this.withNotes) : super(AppConfig.fromEnvironment());
  final bool withNotes;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => withNotes
      ? [
          Entry(
            date: '$year-${month.toString().padLeft(2, '0')}-02',
            taken: true,
            notes: 'a note',
            heart: true,
            period: true,
          ),
        ]
      : const [];

  @override
  Future<CycleInfo> getCycle(String today) async => CycleInfo.empty;
}

/// Cell size, top of the first week row and month arrow position, keyed by
/// how many week rows the visible month has.
Future<Map<int, List<Object>>> _measure(
  WidgetTester tester,
  Size size,
  bool withNotes,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildApp217Theme(
      brightness: Brightness.dark,
      palette: AppPalette.blue,
    ),
    home: CalendarScreen(
      api: _Api(withNotes),
      user: const User(id: 'u1', email: 'o@example.invalid', name: 'O'),
      strings: const Strings(AppLanguage.en),
      onOpenSettings: () {},
    ),
  ));
  await tester.pumpAndSettle();

  final out = <int, List<Object>>{};
  final cells = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_DayCell',
  );
  for (var i = 0; i < 14; i++) {
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 40; i++) {
    final visible = cells
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .where((r) => r.left >= 0 && r.right <= size.width)
        .toList();
    final top = visible.map((r) => r.top).reduce((a, b) => a < b ? a : b);
    final rows = visible.map((r) => r.top).toSet().length;
    final sig = <Object>[
      top.toStringAsFixed(1),
      visible.first.size.toString(),
      tester.getTopLeft(find.byTooltip('Next month')).toString(),
    ];
    out.putIfAbsent(rows, () => sig);
    expect(sig, out[rows]);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(1600, 1000), Size(400, 850)]) {
    testWidgets('grid stays in place for 4, 5 and 6 rows at $size',
        (tester) async {
      final plain = await _measure(tester, size, false);
      expect(plain.keys.toSet(), {4, 5, 6});
      if (size.width >= 560) {
        expect(plain[4], plain[5]);
        expect(plain[5], plain[6]);
      } else {
        // Phones fit each month's rows, but the header and first row stay put.
        for (final i in [0, 2]) {
          expect(plain[4]![i], plain[5]![i]);
          expect(plain[5]![i], plain[6]![i]);
        }
      }
    });

    testWidgets('notes do not move the grid at $size', (tester) async {
      final plain = await _measure(tester, size, false);
      await tester.pumpWidget(const SizedBox());
      final noted = await _measure(tester, size, true);
      expect(noted, plain);
    });
  }
}
