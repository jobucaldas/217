import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig({
    required String apiBaseUrl,
    required this.workosClientId,
    required this.redirectUri,
  })  : defaultApiBaseUrl = normalizeApiBase(apiBaseUrl),
        apiBaseUrl = normalizeApiBase(apiBaseUrl);

  /// Server baked into this build (`API_BASE_URL`); empty means same-origin.
  final String defaultApiBaseUrl;

  /// Server currently in use — the default unless a self-hosted URL was saved.
  String apiBaseUrl;
  final String workosClientId;
  final String redirectUri;

  bool get usesCustomApiBase => apiBaseUrl != defaultApiBaseUrl;

  /// Public client ID only — never pass WORKOS_API_KEY into the Flutter binary.
  factory AppConfig.fromEnvironment() {
    // Web defaults to same-origin (empty). Android emulator defaults to 10.0.2.2.
    const configured = String.fromEnvironment('API_BASE_URL');
    final apiBaseUrl = configured.isNotEmpty
        ? configured
        : (kIsWeb ? '' : 'http://10.0.2.2:8787');
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

/// Trims whitespace and trailing slashes from a server URL.
String normalizeApiBase(String value) =>
    value.trim().replaceAll(RegExp(r'/+$'), '');
