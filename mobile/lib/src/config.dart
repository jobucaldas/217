import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig({
    required String apiBaseUrl,
    required this.workosClientId,
    required this.redirectUri,
  }) : apiBaseUrl = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  String apiBaseUrl;
  final String workosClientId;
  final String redirectUri;

  /// Public client ID only — never pass WORKOS_API_KEY into the Flutter binary.
  factory AppConfig.fromEnvironment() {
    // Web defaults to same-origin (empty). Android emulator defaults to 10.0.2.2.
    const configured = String.fromEnvironment('API_BASE_URL');
    final apiBaseUrl = configured.isNotEmpty
        ? configured
        : (kIsWeb ? '' : 'http://10.0.2.2:8080');
    const workosClientId = String.fromEnvironment(
      'WORKOS_CLIENT_ID',
      defaultValue: 'client_01M3QCMK75B35RPC8EAJA5GREP',
    );
    const redirectUri = String.fromEnvironment(
      'WORKOS_REDIRECT_URI',
      defaultValue: 'com.jobucaldas.a217://auth/callback',
    );
    return AppConfig(
      apiBaseUrl: apiBaseUrl,
      workosClientId: workosClientId,
      redirectUri: redirectUri,
    );
  }
}
