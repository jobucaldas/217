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
import 'package:a217/src/platform/save_data.dart';
import 'package:a217/src/platform/share_sheet.dart';
import 'package:a217/src/screens/privacy_screens.dart';
import 'package:a217/src/theme/app_theme.dart';

/// A signed-in account that has not agreed to the privacy notice yet.
class _ConsentServer {
  bool consented = false;
  bool staleOnce = false;
  int? acceptedVersion;
  bool loggedOut = false;
  final calls = <String>[];

  Map<String, dynamic> _session() => {
        'user': {
          'id': 'u1',
          'email': 'me@example.com',
          'name': 'Me',
          'role': ''
        },
        'share': {'status': 'none', 'can_edit_calendar': false},
        'consent': {'version': 1, 'required': !consented},
      };

  ApiClient client() => ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add('${request.method} $path');
          switch (path) {
            case '/api/auth/session':
              return http.Response(jsonEncode(_session()), 200);
            case '/api/auth/config':
              return http.Response(
                jsonEncode(
                    {'authkit': true, 'privacy_contact': 'dpo@example.com'}),
                200,
              );
            case '/api/account/consent':
              acceptedVersion = (jsonDecode(request.body) as Map)['version'] as int;
              if (staleOnce) { staleOnce=false; return http.Response('{"error":"privacy notice changed","consent_version":2}',409); }
              consented = true;
              return http.Response(jsonEncode(_session()), 200);
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

  for (final brightness in Brightness.values) {
    testWidgets('consent screen gates the app until agreed ($brightness)',
        (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
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
  }

  testWidgets('409 consent refreshes and displays the new notice version', (tester) async {
    final server = _ConsentServer()..staleOnce = true;
    final api = server.client();
    await tester.pumpWidget(App217(config: api.config, api: api));
    await tester.pumpAndSettle();
    final accept=find.byKey(const ValueKey('consent-accept'));
    await tester.scrollUntilVisible(accept,200); await tester.ensureVisible(accept); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consent-checkbox'))); await tester.pump(); await tester.tap(accept); await tester.pumpAndSettle();
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(server.calls.where((c)=>c=='PUT /api/account/consent').length,1);
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
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    addTearDown(()=>debugDefaultTargetPlatformOverride=null);
    final calls=<MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(intentsChannel,(call) async { calls.add(call); return null; });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(intentsChannel,null));
    await shareJsonFile('217-data-2026-10-13.json','{"ok":true}');
    expect(calls.single.method,'shareFile');
    expect((calls.single.arguments as Map)['name'],'217-data-2026-10-13.json');
    expect((calls.single.arguments as Map)['content'],'{"ok":true}');
    expect(calls.where((call)=>call.method=='shareText'),isEmpty);
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
