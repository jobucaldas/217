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
  ApiClient(this.config, {http.Client? httpClient, FlutterSecureStorage? storage})
      : _http = httpClient ?? createPlatformHttpClient(),
        _storage = storage ?? const FlutterSecureStorage();

  final AppConfig config;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  static const _sessionKey = 'session_token';
  static const _apiBaseKey = 'api_base_url';

  Future<void> loadPersistedApiBase() async {
    final saved = await _storage.read(key: _apiBaseKey);
    if (saved != null && saved.trim().isNotEmpty) {
      config.apiBaseUrl = saved.trim().replaceAll(RegExp(r'/+$'), '');
    }
  }

  Future<void> setApiBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      // Empty means same-origin (web).
      config.apiBaseUrl = '';
      await _storage.write(key: _apiBaseKey, value: '');
      return;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('API base URL must include scheme and host');
    }
    config.apiBaseUrl = normalized;
    await _storage.write(key: _apiBaseKey, value: normalized);
  }

  Future<String?> readSessionToken() => _storage.read(key: _sessionKey);

  Future<void> saveSessionToken(String token) =>
      _storage.write(key: _sessionKey, value: token);

  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = config.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
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
    final streamed = await _http.send(request).timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  Future<bool> ping() async {
    try {
      final response = await _send('GET', _uri('/api/auth/session'), auth: false);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
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

  Future<User?> currentUser() async {
    final snapshot = await currentSession();
    return snapshot.user;
  }

  Future<User> signInWithWorkOS() async {
    final pkce = _Pkce.generate();
    final authorize = Uri.https('api.workos.com', '/user_management/authorize', {
      'client_id': config.workosClientId,
      'redirect_uri': config.redirectUri,
      'response_type': 'code',
      'provider': 'authkit',
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
      'state': pkce.state,
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authorize.toString(),
      callbackUrlScheme: 'com.jobucaldas.a217',
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
      throw StateError('WorkOS exchange failed (${response.statusCode}): ${response.body}');
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
      throw StateError('delete account failed: ${response.body}');
    }
    // Only clear local tokens after the server confirms WorkOS + app data deletion.
    await clearSession();
  }

  Future<ShareState> getShare() async {
    final response = await _send('GET', _uri('/api/share'));
    if (response.statusCode != 200) {
      throw StateError('get share failed: ${response.body}');
    }
    return ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> enableShare() async {
    final response = await _send('POST', _uri('/api/share/enable'), body: {});
    if (response.statusCode != 200) {
      throw StateError('enable share failed: ${response.body}');
    }
    return ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> revokeShare() async {
    final response = await _send('POST', _uri('/api/share/revoke'), body: {});
    if (response.statusCode != 200) {
      throw StateError('revoke share failed: ${response.body}');
    }
    return ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ShareState> acceptShare(String code) async {
    final response = await _send(
      'POST',
      _uri('/api/share/accept'),
      body: {'code': code},
    );
    if (response.statusCode != 200) {
      throw StateError('accept share failed: ${response.body}');
    }
    return ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<PartnerNote>> listInbox() async {
    final response = await _send('GET', _uri('/api/inbox'));
    if (response.statusCode != 200) {
      throw StateError('inbox failed: ${response.body}');
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
      throw StateError('partner note failed: ${response.body}');
    }
    return PartnerNote.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> markInboxNoteRead(String id) async {
    final response = await _send('POST', _uri('/api/inbox/$id/read'), body: {});
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw StateError('mark note read failed: ${response.body}');
    }
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
      throw StateError('list entries failed: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = (decoded['entries'] as List<dynamic>? ?? const [])
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    return entries;
  }

  Future<Entry> upsertEntry(
    String date, {
    required bool taken,
    String notes = '',
    bool heart = false,
  }) async {
    final response = await _send(
      'POST',
      _uri('/api/entries/$date'),
      body: {'taken': taken, 'notes': notes, 'heart': heart},
    );
    if (response.statusCode != 200) {
      throw StateError('upsert entry failed: ${response.body}');
    }
    return Entry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteEntry(String date) async {
    final response = await _send('DELETE', _uri('/api/entries/$date'));
    if (response.statusCode == 404) {
      return; // already cleared
    }
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw StateError('delete entry failed: ${response.body}');
    }
  }

  Future<ReminderPreference?> getReminderPreference() async {
    final response = await _send('GET', _uri('/api/reminders/preferences'));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('reminder preference failed: ${response.body}');
    }
    return ReminderPreference.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
    if (response.statusCode == 409) {
      throw StateError('needs_push');
    }
    if (response.statusCode != 200) {
      throw StateError('save reminder failed: ${response.body}');
    }
    return ReminderPreference.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<({bool configured, String publicKey})> vapidConfig() async {
    final response = await _send('GET', _uri('/api/reminders/vapid-public-key'));
    if (response.statusCode != 200) {
      return (configured: false, publicKey: '');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      configured: decoded['configured'] as bool? ?? false,
      publicKey: (decoded['public_key'] as String?) ?? '',
    );
  }

  Future<AuthConfig> authConfig() async {
    final response = await _send('GET', _uri('/api/auth/config'), auth: false);
    if (response.statusCode != 200) {
      return const AuthConfig(authkit: false, password: false);
    }
    return AuthConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
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
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    return _Pkce(verifier: verifier, challenge: challenge, state: randomUrl(16));
  }
}
