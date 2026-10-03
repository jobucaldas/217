import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
