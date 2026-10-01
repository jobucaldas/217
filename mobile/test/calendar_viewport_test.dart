import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

class _FakeCalendarApi extends ApiClient {
  _FakeCalendarApi() : super(AppConfig.fromEnvironment());

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];

  @override
  Future<Entry> upsertEntry(
    String date, {
    required bool taken,
    String notes = '',
  }) async =>
      Entry(date: date, taken: taken, notes: notes);

  @override
  Future<void> deleteEntry(String date) async {}
}

/// Representative monitor / window sizes where the month grid used to crop.
const _viewports = <(String, Size)>[
  ('phone', Size(390, 844)),
  ('phone_short', Size(360, 640)),
  ('laptop_short', Size(1280, 700)),
  ('ultrawide_short', Size(1920, 720)),
  ('tablet', Size(820, 1180)),
  ('desktop', Size(1440, 900)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final (name, size) in _viewports) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'calendar fits full month on $name / ${brightness.name}',
        (tester) async {
          final errors = <FlutterErrorDetails>[];
          final old = FlutterError.onError;
          FlutterError.onError = (details) {
            errors.add(details);
            old?.call(details);
          };
          addTearDown(() => FlutterError.onError = old);

          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              theme: buildApp217Theme(
                brightness: brightness,
                palette: AppPalette.azure,
              ),
              home: MediaQuery(
                data: MediaQueryData(size: size),
                child: CalendarScreen(
                  api: _FakeCalendarApi(),
                  user: const User(
                    id: 'u1',
                    email: 'shot@example.invalid',
                    name: 'Shot',
                  ),
                  strings: Strings(false),
                  onLogout: () async {},
                  onOpenSettings: () {},
                  palette: AppPalette.azure,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('217'), findsOneWidget);
          // Last day of a 31-day month must be on screen (no crop).
          final now = DateTime.now();
          final lastDay =
              DateTime(now.year, now.month + 1, 0).day.toString();
          expect(find.text(lastDay), findsWidgets);

          final overflow = errors.where(
            (e) =>
                e.toString().contains('overflowed') ||
                e.toString().contains('RenderFlex'),
          );
          expect(
            overflow,
            isEmpty,
            reason: 'overflow on $name/${brightness.name}: $overflow',
          );
        },
      );
    }
  }

  test('pinned dark scaffold is #121212 for every accent', () {
    for (final p in AppPalette.values) {
      expect(
        scaffoldBackgroundFor(Brightness.dark, palette: p),
        const Color(0xFF121212),
      );
      expect(
        buildApp217ColorScheme(Brightness.dark, palette: p).surface,
        const Color(0xFF1C1C1C),
      );
    }
  });
}
