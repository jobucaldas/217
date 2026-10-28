import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/platform/save_data.dart';
import 'package:a217/src/platform/share_sheet.dart';
import 'package:a217/src/screens/privacy_screens.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

/// A signed-in account that has not agreed to the privacy notice yet.
class _ConsentServer {
  bool consented = false;
  bool staleOnce = false;
  int consentVersion = 1;
  int? acceptedVersion;
  bool loggedOut = false;
  String role = '';
  bool reminderEnabled = false;
  String reminderTime = '09:00';
  int reminderPreferenceCalls = 0;
  Completer<void>? sessionRefreshGate;
  final calls = <String>[];

  Map<String, dynamic> _session() => {
        'user': {
          'id': 'u1',
          'email': 'me@example.com',
          'name': 'Me',
          'role': role
        },
        'share': {'status': 'none', 'can_edit_calendar': false},
        'consent': {'version': consentVersion, 'required': !consented},
      };

  ApiClient client() => ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add('${request.method} $path');
          switch (path) {
            case '/api/auth/session':
              await sessionRefreshGate?.future;
              return http.Response(jsonEncode(_session()), 200);
            case '/api/auth/config':
              return http.Response(
                jsonEncode(
                    {'authkit': true, 'privacy_contact': 'dpo@example.com'}),
                200,
              );
            case '/api/account/consent':
              acceptedVersion =
                  (jsonDecode(request.body) as Map)['version'] as int;
              if (staleOnce) {
                staleOnce = false;
                consentVersion = 2;
                return http.Response(
                    '{"error":"privacy notice changed","consent_version":2}',
                    409);
              }
              consented = true;
              return http.Response(jsonEncode(_session()), 200);
            case '/api/reminders/preferences':
              reminderPreferenceCalls++;
              if (!consented) {
                return http.Response('{"error":"consent required"}', 403);
              }
              return http.Response(
                jsonEncode({
                  'enabled': reminderEnabled,
                  'time': reminderTime,
                  'timezone': 'UTC',
                  'deliverable': true,
                }),
                200,
              );
            case '/api/entries':
              return consented
                  ? http.Response('{"entries":[]}', 200)
                  : http.Response('{"error":"consent required"}', 403);
            case '/api/cycle':
              return consented
                  ? http.Response(
                      '{"cycle_length":28,"period_length":5,"estimated":true}',
                      200,
                    )
                  : http.Response('{"error":"consent required"}', 403);
            case '/api/auth/logout':
              loggedOut = true;
              return http.Response('{"status":"ok"}', 200);
          }
          // Data endpoints refuse until consent, like the server does.
          return http.Response('{"error":"consent required"}', 403);
        }),
      );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('consent screen gates the app until agreed',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pending_invite': 'ABCD1234'});
    final server = _ConsentServer();
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Your data and privacy'), findsOneWidget);
    expect(find.text('Sensitive health data'), findsOneWidget);
    expect(find.text('dpo@example.com'), findsOneWidget);
    // Nothing is loaded and no invite offered before consent.
    expect(server.calls.where((c) => c.contains('/api/reminders')), isEmpty);
    expect(find.text('Join the shared calendar?'), findsNothing);

    final accept = find.byKey(const ValueKey('consent-accept'));
    await tester.scrollUntilVisible(accept, 200);
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(server.acceptedVersion, 1);
    // The invite waited for consent and is offered now.
    expect(find.text('Join the shared calendar?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('How will you use 217?'), findsOneWidget);
  });

  testWidgets('409 refreshes metadata but blocks unsupported notice versions',
      (tester) async {
    final server = _ConsentServer()..staleOnce = true;
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
    final accept = find.byKey(const ValueKey('consent-accept'));
    await tester.scrollUntilVisible(accept, 200);
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    server.sessionRefreshGate = Completer<void>();
    await tester.tap(accept);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<ConsentScreen>(find.byType(ConsentScreen)).version, 1);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('consent-checkbox')))
            .value,
        isFalse);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    server.sessionRefreshGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(server.consentVersion, 2, reason: server.calls.join(', '));
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(tester.widget<ConsentScreen>(find.byType(ConsentScreen)).version, 2);
    expect(
        find.byKey(const ValueKey('consent-update-required')), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('consent-checkbox')))
            .value,
        isFalse);
    expect(
      tester
          .widget<CheckboxListTile>(
              find.byKey(const ValueKey('consent-checkbox')))
          .onChanged,
      isNull,
    );
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    expect(
        server.calls.where((c) => c == 'PUT /api/account/consent').length, 1);
    expect(find.byKey(const ValueKey('consent-decline')), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final download = find.text('Download my data').last;
    await tester.scrollUntilVisible(
      download,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(download, findsOneWidget);
    expect(server.acceptedVersion, 1);
    expect(
        server.calls.where((c) => c == 'PUT /api/account/consent').length, 1);
  });

  testWidgets('consent acceptance restores saved owner reminder after cancel',
      (tester) async {
    final server = _ConsentServer()
      ..role = 'owner'
      ..reminderEnabled = true
      ..reminderTime = '07:35';
    final api = server.client();
    final cancelGate = Completer<LocalReminderSyncResult>();
    final reminderOperations = <String>[];
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      partnerAlertCanceller: () async {},
      dailyReminderScheduler: ({
        required enabled,
        required timeHhMm,
        required title,
        required body,
        repeatEnabled = false,
        repeatMinutes = 15,
        todayLogged = false,
      }) async {
        if (enabled) {
          reminderOperations.add('schedule:$timeHhMm');
          return const LocalReminderSyncResult(
            LocalReminderSyncStatus.scheduled,
          );
        }
        reminderOperations.add('cancel-start');
        final result = await cancelGate.future;
        reminderOperations.add('cancel-finished');
        return result;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(reminderOperations, ['cancel-start']);

    final accept = find.byKey(const ValueKey('consent-accept'));
    await tester.scrollUntilVisible(accept, 200);
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consent-checkbox')));
    await tester.pump();
    await tester.tap(accept);
    await tester.pumpAndSettle();

    // The accepted session can be displayed immediately, but must wait for
    // the startup cancellation before it reads and restores the saved plan.
    expect(reminderOperations, ['cancel-start']);
    expect(server.reminderPreferenceCalls, 0);
    cancelGate.complete(
      const LocalReminderSyncResult(LocalReminderSyncStatus.cancelled),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    // Consent restore and the newly-mounted calendar's own initial load both
    // ask for a resync around the same time; the second arrives while the
    // first is still waiting on the cancel above, so it runs again right
    // after as a trailing sync (same saved plan, so the same schedule call
    // twice) rather than silently joining a read it arrived too late for.
    expect(
      reminderOperations,
      ['cancel-start', 'cancel-finished', 'schedule:07:35', 'schedule:07:35'],
      reason:
          'role=${server.role}, preferenceCalls=${server.reminderPreferenceCalls}, calls=${server.calls}',
    );
    expect(server.reminderPreferenceCalls, 2);
  });

  testWidgets('settings hide consent-gated controls until agreed',
      (tester) async {
    final server = _ConsentServer()..role = 'owner';
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    // Reminders, sharing, role and stage need data the server refuses yet.
    expect(find.text(const Strings(AppLanguage.en).reminders), findsNothing);
    expect(find.byKey(const ValueKey('stage-cycling')), findsNothing);
    expect(find.byKey(const ValueKey('settings-switch-partner')), findsNothing);
    final download = find.text('Download my data');
    await tester.scrollUntilVisible(
      download,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(download, findsOneWidget);
  });

  testWidgets('a notice change while Settings is open returns to consent',
      (tester) async {
    final server = _ConsentServer()
      ..consented = true
      ..role = 'owner';
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: _noScheduler,
      partnerAlertCanceller: () async {},
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();

    // The operator publishes a new notice; the next save is refused.
    server.consented = false;
    final stage = find.byKey(const ValueKey('stage-menopause'));
    await tester.scrollUntilVisible(stage, 200, scrollable: _settingsList);
    await tester.tap(stage);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stage-menopause')), findsNothing);
    expect(find.byType(ConsentScreen), findsOneWidget);
  });

  testWidgets('logging out cancels partner alerts on the device',
      (tester) async {
    var cancelled = 0;
    final server = _ConsentServer()
      ..consented = true
      ..role = 'partner';
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: _noScheduler,
      partnerAlertCanceller: () async => cancelled++,
    ));
    await tester.pumpAndSettle();
    expect(cancelled, 0);

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    final logout = find.text('Log out');
    await tester.scrollUntilVisible(logout, 200, scrollable: _settingsList);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(server.loggedOut, isTrue);
    expect(cancelled, 1);
  });

  test('the client reports refused consent to its listener', () async {
    var calls = 0;
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((request) async =>
          request.url.path == '/api/reminders/preferences'
              ? http.Response('{"error":"consent required"}', 403)
              : http.Response('{"error":"forbidden"}', 403)),
    )..onConsentRequired = () => calls++;
    await api.getReminderPreference().catchError((Object _) => null);
    expect(calls, 1);
    await api.exportData().catchError((Object _) => '');
    expect(calls, 1);
  });

  testWidgets('declining consent signs out', (tester) async {
    final server = _ConsentServer();
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();

    final decline = find.byKey(const ValueKey('consent-decline'));
    await tester.scrollUntilVisible(decline, 200);
    await tester.ensureVisible(decline);
    await tester.pumpAndSettle();
    await tester.tap(decline);
    await tester.pumpAndSettle();
    expect(server.loggedOut, isTrue, reason: server.calls.join(', '));
    expect(server.acceptedVersion, isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  test('Android export invokes JSON file channel with name and body', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(intentsChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(intentsChannel, null));
    await shareJsonFile('217-data-2026-10-13.json', '{"ok":true}');
    expect(calls.single.method, 'shareFile');
    expect((calls.single.arguments as Map)['name'], '217-data-2026-10-13.json');
    expect((calls.single.arguments as Map)['content'], '{"ok":true}');
    expect(calls.where((call) => call.method == 'shareText'), isEmpty);
  });

  testWidgets('download my data hands the export to the platform',
      (tester) async {
    String? savedName, savedContent;
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/account/export');
        return http.Response('{"user":{"email":"me@example.com"}}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: Scaffold(
          body: DownloadDataTile(
            api: api,
            strings: const Strings(AppLanguage.en),
            save: (name, content) async {
              savedName = name;
              savedContent = content;
              return const SaveDataOutcome(SaveDataHow.downloaded);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Download my data'));
    await tester.pumpAndSettle();
    expect(savedName, matches(RegExp(r'^217-data-\d{4}-\d{2}-\d{2}\.json$')));
    expect(savedContent, contains('me@example.com'));
    expect(find.text('Download started'), findsOneWidget);
  });
}

/// The Settings page's own list, not a horizontal row inside it.
final _settingsList = find
    .descendant(
        of: find.byType(SettingsPage), matching: find.byType(Scrollable))
    .first;

Future<LocalReminderSyncResult> _noScheduler({
  required bool enabled,
  required String timeHhMm,
  required String title,
  required String body,
  bool repeatEnabled = false,
  int repeatMinutes = 15,
  bool todayLogged = false,
}) async =>
    const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled);
