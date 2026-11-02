// Renders the app's real screens with sample data into ../assets/ for the store
// listing. Not part of `flutter test` (it lives outside test/); run it through
// ../render-screenshots.sh, which passes --update-goldens.
//
// The sample data is relative to today's date, so the calendars always show a
// full previous month and upcoming predictions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/partner_alerts_screen.dart';
import 'package:a217/src/screens/share_screens.dart';
import 'package:a217/src/theme/app_theme.dart';

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
DateTime _ago(int d) => _today.subtract(Duration(days: d));
DateTime _ahead(int d) => _today.add(Duration(days: d));

List<Entry> _entries() => [
      for (var i = 1; i <= 75; i++)
        Entry(
          date: _key(_ago(i)),
          taken: !(i == 3 || i == 19 || i == 44),
          notes: '',
          heart: i == 6 || i == 13 || i == 27 || i == 41,
          // Period logged 8-4 days ago and 36-32 days ago.
          period: (i >= 4 && i <= 8) || (i >= 32 && i <= 36),
        ),
    ];

CycleInfo _cycle() => CycleInfo(
      cycleLength: 28,
      periodLength: 5,
      estimated: false,
      periodStarts: [_ago(36), _ago(8)],
      predictions: [
        CycleWindow(
          periodStart: _ahead(20),
          periodEnd: _ahead(24),
          pmsStart: _ahead(13),
          pmsEnd: _ahead(19),
        ),
      ],
    );

class _Api extends ApiClient {
  _Api(this.lang) : super(AppConfig.fromEnvironment());
  final AppLanguage lang;

  @override
  Future<List<Entry>> listEntries(int year, int month) async => _entries()
      .where((e) =>
          e.date.startsWith('$year-${month.toString().padLeft(2, '0')}'))
      .toList();

  @override
  Future<CycleInfo> getCycle(String today) async => _cycle();

  @override
  Future<PartnerAlertPreference> getPartnerAlerts() async =>
      const PartnerAlertPreference(
        pmsEnabled: true,
        pmsTime: '09:00',
        pillEnabled: true,
        pillTime: '21:30',
      );

  @override
  Future<List<InboxMessage>> listInbox() async {
    final t = switch (lang) {
      AppLanguage.en => [
          'Thanks for the heads up, I will bring chocolate tonight.',
          'Cramps are starting, PMS week is here.',
          'Pill taken, all good today.',
        ],
      AppLanguage.pt => [
          'Obrigado por avisar, levo chocolate hoje à noite.',
          'As cólicas estão começando, semana de TPM chegando.',
          'Pílula tomada, tudo certo hoje.',
        ],
      AppLanguage.es => [
          'Gracias por avisar, llevo chocolate esta noche.',
          'Empiezan los cólicos, llega la semana de SPM.',
          'Píldora tomada, todo bien hoy.',
        ],
    };
    return [
      InboxMessage(
          id: '3',
          body: t[0],
          createdAt: _now.subtract(const Duration(minutes: 12)),
          fromMe: true),
      InboxMessage(
          id: '2',
          body: t[1],
          createdAt: _now.subtract(const Duration(hours: 1, minutes: 5)),
          fromName: 'Ana Souza',
          readAt: _now),
      InboxMessage(
          id: '1',
          body: t[2],
          createdAt: _now.subtract(const Duration(hours: 5)),
          fromName: 'Ana Souza',
          readAt: _now),
    ];
  }
}

const _owner =
    User(id: 'o', email: 'ana@example.com', name: 'Ana Souza', role: 'owner');
const _partner = User(
    id: 'p', email: 'bruno@example.com', name: 'Bruno Lima', role: 'partner');
const _sharedOwner = ShareState(
    status: 'active',
    partnerName: 'Bruno Lima',
    partnerEmail: 'bruno@example.com',
    canEditCalendar: true,
    unreadNotes: 2);
const _sharedPartner = ShareState(
    status: 'active',
    ownerName: 'Ana Souza',
    ownerEmail: 'ana@example.com',
    canEditCalendar: false,
    unreadNotes: 1);

/// Play wants 16:9 or 9:16; each folder under assets/ is one console section.
const _shapes = <({String dir, int w, int h, double dpr})>[
  (dir: 'phone-screenshots', w: 1080, h: 1920, dpr: 3),
  (dir: 'tablet-7in-screenshots', w: 1080, h: 1920, dpr: 2),
];

const _locales = {
  AppLanguage.en: 'en-US',
  AppLanguage.pt: 'pt-BR',
  AppLanguage.es: 'es-419',
};

/// The app ships its fonts as assets for google_fonts; tests also need the
/// Material icon font from the SDK, or icons render as boxes.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  const weights = {
    'regular': 'Regular',
    '500': 'Medium',
    '600': 'SemiBold',
    '700': 'Bold',
  };
  for (final e in weights.entries) {
    await load('SourceSans3_${e.key}', ['assets/fonts/SourceSans3-${e.value}.ttf']);
    await load('Fraunces_${e.key}', ['assets/fonts/Fraunces-${e.value}.ttf']);
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  await load('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting();
  });

  for (final shape in _shapes) {
    for (final lang in AppLanguage.values) {
      final strings = Strings(lang);
      final api = _Api(lang);
      final out = '../../assets/${shape.dir}/${_locales[lang]}';
      final name = '${shape.dir} ${lang.name}';

      Future<void> pump(WidgetTester t, Widget home, Brightness b) async {
        t.view.physicalSize = Size(shape.w.toDouble(), shape.h.toDouble());
        t.view.devicePixelRatio = shape.dpr;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildApp217Theme(brightness: b, palette: AppPalette.blue),
          home: home,
        ));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
      }

      Future<void> shot(String file) => expectLater(
          find.byType(MaterialApp), matchesGoldenFile('$out/$file.png'));

      Future<void> lastMonth(WidgetTester t) async {
        await t.tap(find.byIcon(Icons.chevron_left));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
      }

      CalendarScreen calendar(User u, ShareState s) => CalendarScreen(
            api: api,
            user: u,
            share: s,
            strings: strings,
            onOpenSettings: () {},
          );

      testWidgets('$name history', (t) async {
        await pump(t, calendar(_owner, _sharedOwner), Brightness.dark);
        await lastMonth(t);
        await shot('01-calendar');
      });

      testWidgets('$name predictions', (t) async {
        await pump(t, calendar(_owner, _sharedOwner), Brightness.dark);
        await shot('02-predictions');
      });

      testWidgets('$name day editor', (t) async {
        await pump(t, calendar(_owner, _sharedOwner), Brightness.dark);
        await t.tap(find.byKey(const ValueKey('update-day-button')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await shot('03-log-a-day');
      });

      testWidgets('$name partner', (t) async {
        await pump(t, calendar(_partner, _sharedPartner), Brightness.light);
        await lastMonth(t);
        await shot('04-partner-view');
      });

      testWidgets('$name messages', (t) async {
        await pump(t, InboxScreen(api: api, strings: strings, canSend: true),
            Brightness.dark);
        await shot('05-messages');
      });

      testWidgets('$name partner alerts', (t) async {
        await pump(
            t,
            PartnerAlertsScreen(
                api: api, strings: strings, share: _sharedPartner),
            Brightness.light);
        await shot('06-partner-alerts');
      });
    }
  }
}
