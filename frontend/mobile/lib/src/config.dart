import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig({
    required String apiBaseUrl,
    required this.workosClientId,
    required this.redirectUri,
  })  : defaultApiBaseUrl = normalizeApiBase(apiBaseUrl),
        apiBaseUrl = normalizeApiBase(apiBaseUrl);

  /// Server baked into this build (`API_BASE_URL`). Empty means same-origin
  /// on web and no server at all on Android (release APKs ask for one).
  final String defaultApiBaseUrl;

  /// Server currently in use — the default unless a self-hosted URL was saved.
  String apiBaseUrl;

  /// Fallback only: servers report their own public client ID.
  final String workosClientId;
  final String redirectUri;

  bool get usesCustomApiBase => apiBaseUrl != defaultApiBaseUrl;

  /// False for release APKs: there is no server to fall back to, so the
  /// server is set up on first launch instead of in Settings.
  bool get hasDefaultServer => kIsWeb || defaultApiBaseUrl.isNotEmpty;

  /// No server to talk to yet: the app asks for one before sign-in.
  bool get needsServerSetup => !kIsWeb && apiBaseUrl.isEmpty;

  /// Public client ID only — never pass WORKOS_API_KEY into the Flutter binary.
  factory AppConfig.fromEnvironment() {
    // Web defaults to same-origin (empty). Debug Android builds default to the
    // emulator's host (10.0.2.2); release APKs have no server unless one is
    // baked in with API_BASE_URL, so people connect their own on first launch.
    const configured = String.fromEnvironment('API_BASE_URL');
    final apiBaseUrl = configured.isNotEmpty
        ? configured
        : (kIsWeb || kReleaseMode ? '' : 'http://10.0.2.2:8787');
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
