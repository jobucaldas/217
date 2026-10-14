import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';

const _installed = '20200101000000_abcdef0';
const _newer = '20990101000000_abcdef1';
const _apkUrl =
    'https://github.com/jobucaldas/217/releases/download/$_newer/app-release.apk';

const _en = Strings(AppLanguage.en);

/// Signed in as an owner with no entries; anything unexpected is a 404.
ApiClient _signedInApi() => ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/session':
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'u1',
                  'email': 'a@b.c',
                  'name': 'Owner',
                  'role': 'owner',
                },
                'share': {'status': 'none', 'can_edit_calendar': true},
              }),
              200,
            );
          case '/api/entries':
            return http.Response('{"entries":[]}', 200);
        }
        return http.Response('{"error":"not found"}', 404);
      }),
    );

/// The release request waits on [gate], so the test decides when it answers.
http.Client _releaseClient(Completer<void> gate) => MockClient((request) async {
      await gate.future;
      return http.Response(
        jsonEncode([
          {
            'tag_name': _newer,
            'draft': false,
            'assets': [
              {'name': 'app-release.apk', 'browser_download_url': _apkUrl},
            ],
          },
        ]),
        200,
      );
    });

Future<void> _pumpApp(
  WidgetTester tester,
  ApiClient api,
  Completer<void> gate,
) async {
  await tester.pumpWidget(
    App217(
      config: api.config,
      api: api,
      updateClient: _releaseClient(gate),
      installedVersion: _installed,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The override must be reset inside each body: flutter_test checks it
  // before tearDown runs.
  setUp(() => FlutterSecureStorage.setMockInitialValues({'auto_update': '1'}));

  testWidgets('auto-update on: a newer release shows the Update SnackBar',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final gate = Completer<void>();
    await _pumpApp(tester, _signedInApi(), gate);
    expect(find.text(_en.updateAvailable), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(_en.updateAvailable), findsOneWidget);
    expect(find.text(_en.updateAction), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('switching auto-update off before the release answers hides it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final gate = Completer<void>();
    await _pumpApp(tester, _signedInApi(), gate);

    // Turn the switch off in Settings while the release request is pending.
    await tester.tap(find.byTooltip(_en.settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-auto-update')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('settings-auto-update')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const ValueKey('settings-auto-update')))
          .value,
      isFalse,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'auto_update'),
      '0',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(_en.updateAvailable), findsNothing);
    expect(find.text(_en.updateAction), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
