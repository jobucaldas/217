import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/prefs.dart';
import 'package:a217/src/screens/calendar_screen.dart';
import 'package:a217/src/screens/personal_section.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/stage_suggestion.dart';
import 'package:a217/src/theme/app_theme.dart';

const _en = Strings(AppLanguage.en);
const _owner =
    User(id: 'o', email: 'o@example.com', name: 'Owner', role: 'owner');

class _StageApi extends ApiClient {
  _StageApi(this.suggested) : super(AppConfig.fromEnvironment());

  String? suggested;
  String stage = 'cycling';
  final stagesSet = <String>[];

  @override
  Future<List<Entry>> listEntries(int year, int month) async => const [];

  @override
  Future<CycleInfo> getCycle(String today) async =>
      CycleInfo(stage: stage, suggestedStage: suggested);

  @override
  Future<SessionSnapshot> setStage(String stage) async {
    stagesSet.add(stage);
    this.stage = stage;
    suggested = null;
    return SessionSnapshot(
      user: User(
          id: 'o',
          email: 'o@example.com',
          name: 'Owner',
          role: 'owner',
          stage: stage),
      share: const ShareState(status: 'none'),
    );
  }
}

/// The calendar plus the app's Settings wiring, as in `app.dart`.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.api,
    required this.suggestion,
    this.user,
    this.reminderHint = false,
  });

  final _StageApi api;
  final bool reminderHint;
  final StageSuggestion suggestion;
  final User? user;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _nav = GlobalKey<NavigatorState>();
  late User _user = widget.user ?? _owner;
  final _stageChanges = ValueNotifier<int>(0);

  @override
  void dispose() {
    _stageChanges.dispose();
    super.dispose();
  }

  void _openSettings({bool focusPersonal = false, bool stageUpdated = false}) {
    _nav.currentState!.push(MaterialPageRoute(
      builder: (_) => SettingsPage(
        api: widget.api,
        strings: _en,
        language: AppLanguage.en,
        themeMode: ThemeMode.light,
        palette: AppPalette.blue,
        onLanguageChanged: (_) {},
        onThemeModeChanged: (_) {},
        onPaletteChanged: (_) {},
        onApiBaseChanged: () {},
        onLogout: () async {},
        user: _user,
        share: const ShareState(status: 'none'),
        stageSuggestion: widget.suggestion,
        focusPersonal: focusPersonal,
        stageUpdated: stageUpdated,
        onStageChanged: (session) {
          setState(() => _user = session.user!);
          _stageChanges.value++;
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _nav,
        theme: buildApp217Theme(brightness: Brightness.light),
        home: CalendarScreen(
          api: widget.api,
          user: _user,
          strings: _en,
          onOpenSettings: _openSettings,
          cycleRefreshSignal: _stageChanges,
          stageSuggestion: widget.suggestion,
          showReminderHint: widget.reminderHint,
          onDismissReminderHint: widget.reminderHint ? () {} : null,
          onStageSuggestionAccepted: (session) {
            setState(() => _user = session.user!);
            _stageChanges.value++;
            _openSettings(focusPersonal: true, stageUpdated: true);
          },
        ),
      );
}

final _calendarBanner = find.byKey(const ValueKey('calendar-stage-suggestion'));
final _settingsBanner = find.byKey(const ValueKey('settings-stage-suggestion'));
final _updatedBanner = find.byKey(const ValueKey('stage-updated-banner'));

bool _cogDot(WidgetTester tester) => tester
    .widget<Badge>(find.byKey(const ValueKey('settings-sync-dot')))
    .isLabelVisible;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('suggested_stage is parsed from the cycle answer', () {
    expect(CycleInfo.fromJson({'suggested_stage': 'menopause'}).suggestedStage,
        'menopause');
    expect(CycleInfo.fromJson({}).suggestedStage, isNull);
  });

  testWidgets('Update saves the stage and shows "updated" in Settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _StageApi('perimenopause');
    final suggestion = StageSuggestion();
    await tester.pumpWidget(_Harness(api: api, suggestion: suggestion));
    await tester.pumpAndSettle();

    expect(_calendarBanner, findsOneWidget);
    expect(find.text('You might be in perimenopause'),
        findsOneWidget);
    expect(_cogDot(tester), isFalse);

    await tester.tap(find.descendant(
        of: _calendarBanner,
        matching: find.byKey(const ValueKey('stage-suggestion-update'))));
    await tester.pumpAndSettle();

    expect(api.stagesSet, ['perimenopause']);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('PERSONAL'), findsOneWidget);
    expect(_updatedBanner, findsOneWidget);
    expect(find.text('Updated successfully'), findsOneWidget);
    expect(_settingsBanner, findsNothing);

    await tester.pump(PersonalSection.updatedNoticeDuration);
    await tester.pumpAndSettle();
    expect(_updatedBanner, findsNothing);

    // Back on the calendar: nothing left to suggest.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(_cogDot(tester), isFalse);
  });

  testWidgets('the reminder hint waits until the stage banner is gone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final suggestion = StageSuggestion();
    await tester.pumpWidget(_Harness(
        api: _StageApi('perimenopause'),
        suggestion: suggestion,
        reminderHint: true));
    await tester.pumpAndSettle();
    final hint = find.byKey(const ValueKey('reminder-hint'));
    expect(_calendarBanner, findsOneWidget);
    expect(hint, findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(hint, findsOneWidget);
  });

  testWidgets(
      'an ignored banner closes after 30 s; Settings and the cog dot keep it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _StageApi('menopause');
    final suggestion = StageSuggestion();
    await tester.pumpWidget(_Harness(api: api, suggestion: suggestion));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(_calendarBanner, findsOneWidget);
    expect(_cogDot(tester), isFalse);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(_cogDot(tester), isTrue);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(_settingsBanner, findsOneWidget);
    expect(
        find.text('You might be at menopause'), findsOneWidget);

    await tester.tap(find.descendant(
        of: _settingsBanner,
        matching: find.byKey(const ValueKey('stage-suggestion-dismiss'))));
    await tester.pumpAndSettle();
    expect(_settingsBanner, findsNothing);
    expect(api.stagesSet, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_cogDot(tester), isFalse);
    expect(_calendarBanner, findsNothing);

    // A different suggestion shows again.
    api.suggested = 'perimenopause';
    suggestion.update('o', 'perimenopause');
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsOneWidget);
    await tester.tap(find.descendant(
        of: _calendarBanner,
        matching: find.byKey(const ValueKey('stage-suggestion-dismiss'))));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(_cogDot(tester), isFalse);
  });

  testWidgets('accepting from the Settings banner shows "updated" in place',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _StageApi('perimenopause');
    final suggestion = StageSuggestion();
    await tester.pumpWidget(_Harness(api: api, suggestion: suggestion));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: _settingsBanner,
        matching: find.byKey(const ValueKey('stage-suggestion-update'))));
    await tester.pumpAndSettle();
    expect(api.stagesSet, ['perimenopause']);
    expect(_settingsBanner, findsNothing);
    expect(_updatedBanner, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_updatedBanner, findsNothing);
  });

  testWidgets('the banner shows once; a new session keeps Settings and the dot',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = AppearancePrefs();
    final first = StageSuggestion(prefs: prefs);
    await tester.pumpWidget(_Harness(api: _StageApi('menopause'), suggestion: first));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsOneWidget);
    expect(_cogDot(tester), isFalse);
    // Seen the moment it was shown, before any timeout.
    expect(await prefs.stageSuggestionSeen('o'), 'menopause');

    // App reopened before the 30 s: fresh state, same prefs.
    await tester.pumpWidget(const SizedBox());
    final second = StageSuggestion(prefs: prefs);
    await tester.pumpWidget(_Harness(api: _StageApi('menopause'), suggestion: second));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(_cogDot(tester), isTrue);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(_settingsBanner, findsOneWidget);

    // A different value shows on the home screen once more.
    await tester.pageBack();
    await tester.pumpAndSettle();
    second.update('o', 'perimenopause');
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
  });

  testWidgets('the stage dropdown offers "I don\'t have cycles"',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _StageApi(null);
    await tester.pumpWidget(_Harness(api: api, suggestion: StageSuggestion()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const ValueKey('stage-dropdown'));
    await tester.scrollUntilVisible(dropdown, 200,
        scrollable: find
            .descendant(
                of: find.byType(SettingsPage), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: dropdown, matching: find.byType(TextField)));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I don't have cycles").last);
    await tester.pumpAndSettle();
    expect(api.stagesSet, ['no_cycles']);
  });

  test('suggestion and stage texts are discreet in every language', () {
    const pt = Strings(AppLanguage.pt);
    const es = Strings(AppLanguage.es);
    expect(_en.stageSuggestionBody('perimenopause'),
        'You might be in perimenopause');
    expect(_en.stageSuggestionBody('menopause'), 'You might be at menopause');
    expect(pt.stageSuggestionBody('perimenopause'),
        'Você pode estar na perimenopausa');
    expect(pt.stageSuggestionBody('menopause'), 'Você pode estar na menopausa');
    expect(es.stageSuggestionBody('perimenopause'),
        'Puede que estés en la perimenopausia');
    expect(
        es.stageSuggestionBody('menopause'), 'Puede que estés en la menopausia');
    expect(_en.stageLabel('no_cycles'), "I don't have cycles");
    expect(pt.stageLabel('no_cycles'), 'Não tenho ciclos');
    expect(es.stageLabel('no_cycles'), 'No tengo ciclos');
    expect(_en.cycleStageNote('no_cycles'), isNotEmpty);
  });

  testWidgets('partners never see a suggestion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final suggestion = StageSuggestion();
    await tester.pumpWidget(_Harness(
      api: _StageApi('menopause'),
      suggestion: suggestion,
      user: const User(
          id: 'p', email: 'p@example.com', name: 'P', role: 'partner'),
    ));
    await tester.pumpAndSettle();
    expect(_calendarBanner, findsNothing);
    expect(suggestion.stage, isNull);
    expect(_cogDot(tester), isFalse);
  });
}
