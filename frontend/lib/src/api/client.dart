import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';
import 'platform_http.dart';

class ApiClient {
  ApiClient(this.config,
      {http.Client? httpClient, FlutterSecureStorage? storage})
      : _http = httpClient ?? createPlatformHttpClient(),
        _storage = storage ?? const FlutterSecureStorage();

  final AppConfig config;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  static const _sessionKey = 'session_token';
  static const _apiBaseKey = 'api_base_url';

  Future<void> loadPersistedApiBase() async {
    final saved = normalizeApiBase(await _storage.read(key: _apiBaseKey) ?? '');
    // Missing or empty (older builds stored '' for same-origin) → build default.
    config.apiBaseUrl = saved.isEmpty ? config.defaultApiBaseUrl : saved;
  }

  /// Validates a self-hosted server URL; empty means "use the default server".
  /// A bare host gets `https://`, and a pasted invite link
  /// (`https://host/?invite=CODE`) keeps only its server part.
  /// Throws [FormatException] unless the URL is http(s) with a host.
  static String parseApiBase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        RegExp(r'[\s%]').hasMatch(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('server URL needs http(s):// and a host');
    }
    final server = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return normalizeApiBase(server.toString());
  }

  /// Invite code carried by a pasted invite link, if any.
  static String? inviteCodeIn(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    final code = uri?.queryParameters['invite']?.trim() ?? '';
    return code.isEmpty ? null : code;
  }

  /// Saves a self-hosted server URL (empty resets to the default server).
  /// Returns true when the server changed. The old session token is dropped
  /// then, so it is never sent to a different host.
  Future<bool> setApiBaseUrl(String value) async {
    final parsed = parseApiBase(value);
    final next = parsed.isEmpty ? config.defaultApiBaseUrl : parsed;
    if (next == config.defaultApiBaseUrl) {
      await _storage.delete(key: _apiBaseKey);
    } else {
      await _storage.write(key: _apiBaseKey, value: next);
    }
    if (next == config.apiBaseUrl) return false;
    config.apiBaseUrl = next;
    await clearSession();
    return true;
  }

  Future<String?> readSessionToken() => _storage.read(key: _sessionKey);

  Future<void> saveSessionToken(String token) =>
      _storage.write(key: _sessionKey, value: token);

  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  Uri _uri(String path, [Map<String, String>? query]) =>
      _uriFor(config.apiBaseUrl, path, query);

  static Uri _uriFor(String base, String path, [Map<String, String>? query]) {
    final uri = base.isEmpty ? Uri.parse(path) : Uri.parse('$base$path');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await readSessionToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final streamed =
        await _http.send(request).timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  /// Whether [baseUrl] (default: the current server) is a 217 API that
  /// people can sign in to.
  Future<ServerCheck> checkServer({String? baseUrl}) async {
    final base =
        baseUrl == null ? config.apiBaseUrl : normalizeApiBase(baseUrl);
    final http.Response response;
    try {
      response = await _send(
        'GET',
        _uriFor(base, '/api/auth/config'),
        auth: false,
      );
    } catch (_) {
      return ServerCheck.unreachable;
    }
    if (response.statusCode != 200) return ServerCheck.notA217Server;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || !decoded.containsKey('authkit')) {
        return ServerCheck.notA217Server;
      }
      return decoded['authkit'] == true
          ? ServerCheck.ok
          : ServerCheck.signInNotConfigured;
    } on FormatException {
      return ServerCheck.notA217Server;
    }
  }

  /// The server's public WorkOS client ID, so one APK can sign in to any
  /// self-hosted server. Older servers don't report it: use the build's, if any.
  Future<String> signInClientId() async {
    final response = await _send('GET', _uri('/api/auth/config'), auth: false);
    if (response.statusCode != 200) {
      throw ApiException('auth config', response);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['authkit'] != true) {
      throw StateError('sign-in is not configured on this server');
    }
    final clientId = decoded['workos_client_id'];
    if (clientId is String && clientId.isNotEmpty) return clientId;
    if (config.workosClientId.isNotEmpty) return config.workosClientId;
    throw StateError('server did not report a WorkOS client ID');
  }

  Future<SessionSnapshot> currentSession() async {
    final response = await _send('GET', _uri('/api/auth/session'));
    if (response.statusCode != 200) {
      return const SessionSnapshot();
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final snapshot = SessionSnapshot.fromJson(decoded);
    if (snapshot.user == null) {
      await clearSession();
    }
    return snapshot;
  }

  Future<User> signInWithWorkOS() async {
    final clientId = await signInClientId();
    final pkce = _Pkce.generate();
    final authorize =
        Uri.https('api.workos.com', '/user_management/authorize', {
      'client_id': clientId,
      'redirect_uri': config.redirectUri,
      'response_type': 'code',
      'provider': 'authkit',
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
      'state': pkce.state,
    });

    // Android: deep link claimed by the manifest. Desktop: the plugin listens
    // on the loopback address and the system browser does the sign-in.
    final redirect = Uri.parse(config.redirectUri);
    final result = await FlutterWebAuth2.authenticate(
      url: authorize.toString(),
      callbackUrlScheme: config.usesLoopbackRedirect
          ? '${redirect.scheme}://${redirect.host}:${redirect.port}'
          : redirect.scheme,
      options: const FlutterWebAuth2Options(useWebview: false),
    );
    final returned = Uri.parse(result);
    final code = returned.queryParameters['code'];
    final state = returned.queryParameters['state'];
    if (code == null || code.isEmpty) {
      throw StateError('WorkOS callback missing authorization code');
    }
    if (state != pkce.state) {
      throw StateError('WorkOS callback state mismatch');
    }

    final response = await _send(
      'POST',
      _uri('/api/auth/workos/exchange'),
      body: {
        'code': code,
        'code_verifier': pkce.verifier,
        'redirect_uri': config.redirectUri,
      },
      auth: false,
    );
    if (response.statusCode != 200) {
      throw StateError(
          'WorkOS exchange failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['session_token'] as String?;
    final userJson = decoded['user'] as Map<String, dynamic>?;
    if (token == null || userJson == null) {
      throw StateError('WorkOS exchange response missing session');
    }
    await saveSessionToken(token);
    return User.fromJson(userJson);
  }

  Future<void> logout() async {
    try {
      await _send('POST', _uri('/api/auth/logout'), body: {});
    } finally {
      await clearSession();
    }
  }

  Future<void> deleteAccount() async {
    final response = await _send('DELETE', _uri('/api/account'));
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException('delete account', response);
    }
    // Only clear local tokens after the server confirms WorkOS + app data deletion.
    await clearSession();
  }

  Future<ShareState> getShare() async {
    final response = await _send('GET', _uri('/api/share'));
    if (response.statusCode != 200) {
      throw ApiException('get share', response);
    }
    return ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> enableShare() async {
    final response = await _send('POST', _uri('/api/share/enable'), body: {});
    if (response.statusCode != 200) {
      throw ApiException('enable share', response);
    }
    return ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> revokeShare() async {
    final response = await _send('POST', _uri('/api/share/revoke'), body: {});
    if (response.statusCode != 200) {
      throw ApiException('revoke share', response);
    }
    return ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> acceptShare(String code) async {
    final response = await _send(
      'POST',
      _uri('/api/share/accept'),
      body: {'code': code},
    );
    if (response.statusCode != 200) {
      throw ApiException('accept share', response);
    }
    return ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<PartnerNote>> listInbox() async {
    final response = await _send('GET', _uri('/api/inbox'));
    if (response.statusCode != 200) {
      throw ApiException('inbox', response);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['notes'] as List<dynamic>? ?? const [])
        .map((e) => PartnerNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PartnerNote> createPartnerNote(String body) async {
    final response = await _send(
      'POST',
      _uri('/api/partner-notes'),
      body: {'body': body},
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiException('partner note', response);
    }
    return PartnerNote.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> markInboxNoteRead(String id) async {
    final response = await _send('POST', _uri('/api/inbox/$id/read'), body: {});
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException('mark note read', response);
    }
  }

  /// Owner (takes the pill) or partner (follows her calendar). Returns the
  /// refreshed session.
  Future<SessionSnapshot> setRole(String role) async {
    final response = await _send(
      'PUT',
      _uri('/api/account/role'),
      body: {'role': role},
    );
    if (response.statusCode != 200) {
      throw ApiException('set role', response);
    }
    return SessionSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Period history and predictions for the visible calendar. [today] is the
  /// device's local date (YYYY-MM-DD).
  Future<CycleInfo> getCycle(String today) async {
    final response = await _send('GET', _uri('/api/cycle', {'today': today}));
    if (response.statusCode != 200) {
      throw ApiException('cycle', response);
    }
    return CycleInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<PartnerAlertPreference> getPartnerAlerts() async {
    final response = await _send('GET', _uri('/api/partner-alerts'));
    if (response.statusCode != 200) {
      throw ApiException('partner alerts', response);
    }
    return PartnerAlertPreference.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<PartnerAlertPreference> savePartnerAlerts(
    PartnerAlertPreference pref,
  ) async {
    final response = await _send(
      'PUT',
      _uri('/api/partner-alerts'),
      body: pref.toJson(),
    );
    if (response.statusCode != 200) {
      throw ApiException('save partner alerts', response);
    }
    return PartnerAlertPreference.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<Entry>> listEntries(int year, int month) async {
    final response = await _send(
      'GET',
      _uri('/api/entries', {
        'year': '$year',
        'month': '$month',
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException('list entries', response);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = (decoded['entries'] as List<dynamic>? ?? const [])
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    return entries;
  }

  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
    bool period = false,
  }) async {
    final response = await _send(
      'POST',
      _uri('/api/entries/$date'),
      body: {'taken': taken, 'notes': notes, 'heart': heart, 'period': period},
    );
    if (response.statusCode != 200) {
      throw ApiException('upsert entry', response);
    }
    return Entry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteEntry(String date) async {
    final response = await _send('DELETE', _uri('/api/entries/$date'));
    if (response.statusCode == 404) {
      return; // already cleared
    }
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException('delete entry', response);
    }
  }

  Future<ReminderPreference?> getReminderPreference() async {
    final response = await _send('GET', _uri('/api/reminders/preferences'));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ApiException('reminder preference', response);
    }
    return ReminderPreference.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ReminderPreference> upsertReminderPreference({
    required bool enabled,
    required String time,
    required String timezone,
  }) async {
    final response = await _send(
      'PUT',
      _uri('/api/reminders/preferences'),
      body: {
        'enabled': enabled,
        'time': time,
        'timezone': timezone,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('save reminder', response);
    }
    return ReminderPreference.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<({bool configured, String publicKey})> vapidConfig() async {
    final response =
        await _send('GET', _uri('/api/reminders/vapid-public-key'));
    if (response.statusCode != 200) {
      return (configured: false, publicKey: '');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      configured: decoded['configured'] as bool? ?? false,
      publicKey: (decoded['public_key'] as String?) ?? '',
    );
  }
}

/// Result of [ApiClient.checkServer].
enum ServerCheck { ok, unreachable, notA217Server, signInNotConfigured }

/// Non-success API response. [message] is the server's `error` field, if any.
class ApiException implements Exception {
  ApiException(this.action, http.Response response)
      : statusCode = response.statusCode,
        message = _errorField(response.body);

  final String action;
  final int statusCode;
  final String message;

  static String _errorField(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return '';
  }

  @override
  String toString() =>
      '$action failed ($statusCode)${message.isEmpty ? '' : ': $message'}';
}

class _Pkce {
  _Pkce({required this.verifier, required this.challenge, required this.state});

  final String verifier;
  final String challenge;
  final String state;

  factory _Pkce.generate() {
    final random = Random.secure();
    String randomUrl(int bytes) {
      final values = List<int>.generate(bytes, (_) => random.nextInt(256));
      return base64UrlEncode(values).replaceAll('=', '');
    }

    final verifier = randomUrl(32);
    final challenge =
        base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
            .replaceAll('=', '');
    return _Pkce(
        verifier: verifier, challenge: challenge, state: randomUrl(16));
  }
}
