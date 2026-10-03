import 'package:flutter/foundation.dart';

/// AuthKit callback for Android: a custom scheme claimed in the manifest.
const androidRedirectUri = 'com.jobucaldas.a217://auth/callback';

/// AuthKit callback for desktop: the app listens on this loopback address while
/// the system browser signs in (RFC 8252). Must match the server's allowlist.
const desktopRedirectUri = 'http://localhost:21717/auth/callback';

/// Windows and Linux builds, which have no store, no deep-link intent and no
/// emulator host: they follow Android's server-setup flow with a loopback callback.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

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

  /// Desktop sign-in returns to a local http listener instead of a deep link.
  bool get usesLoopbackRedirect => Uri.parse(redirectUri).scheme == 'http';

  bool get usesCustomApiBase => apiBaseUrl != defaultApiBaseUrl;

  /// False for release APKs: there is no server to fall back to, so the
  /// server is set up on first launch instead of in Settings.
  bool get hasDefaultServer => kIsWeb || defaultApiBaseUrl.isNotEmpty;

  /// No server to talk to yet: the app asks for one before sign-in.
  bool get needsServerSetup => !kIsWeb && apiBaseUrl.isEmpty;

  /// Public client ID only — never pass WORKOS_API_KEY into the Flutter binary.
  factory AppConfig.fromEnvironment() {
    // Web defaults to same-origin (empty). Debug builds default to the local
    // stack (the emulator's host on Android); release apps (APK, Windows,
    // Linux) have no server unless one is baked in with API_BASE_URL, so
    // people connect their own on first launch.
    const configured = String.fromEnvironment('API_BASE_URL');
    final apiBaseUrl = configured.isNotEmpty
        ? configured
        : (kIsWeb || kReleaseMode
            ? ''
            : (isDesktopPlatform
                ? 'http://localhost:8787'
                : 'http://10.0.2.2:8787'));
    const workosClientId = String.fromEnvironment('WORKOS_CLIENT_ID');
    const redirectOverride = String.fromEnvironment('WORKOS_REDIRECT_URI');
    return AppConfig(
      apiBaseUrl: apiBaseUrl,
      workosClientId: workosClientId,
      redirectUri: redirectOverride.isNotEmpty
          ? redirectOverride
          : (isDesktopPlatform ? desktopRedirectUri : androidRedirectUri),
    );
  }
}

/// Trims whitespace and trailing slashes from a server URL.
String normalizeApiBase(String value) =>
    value.trim().replaceAll(RegExp(r'/+$'), '');
