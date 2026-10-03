import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('desktop builds sign in through the loopback callback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final config = AppConfig.fromEnvironment();
    expect(config.redirectUri, desktopRedirectUri);
    expect(config.usesLoopbackRedirect, isTrue);
  });

  test('Android keeps its deep-link callback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final config = AppConfig.fromEnvironment();
    expect(config.redirectUri, androidRedirectUri);
    expect(config.usesLoopbackRedirect, isFalse);
  });

  test('release desktop builds ask for a server like the APK', () {
    final config = AppConfig(
      apiBaseUrl: '',
      workosClientId: 'client_build',
      redirectUri: desktopRedirectUri,
    );
    expect(config.needsServerSetup, isTrue);
  });

  test('sign-in uses the client ID your server reports, none is built in',
      () async {
    AppConfig config() => AppConfig(
          apiBaseUrl: 'https://self.example.com',
          workosClientId: '',
          redirectUri: androidRedirectUri,
        );
    ApiClient api(String body) => ApiClient(
          config(),
          httpClient: MockClient((_) async => http.Response(body, 200)),
        );

    expect(
      await api('{"authkit":true,"workos_client_id":"client_theirs"}')
          .signInClientId(),
      'client_theirs',
    );
    expect(
      api('{"authkit":true}').signInClientId(),
      throwsA(isA<StateError>()),
    );
  });
}
