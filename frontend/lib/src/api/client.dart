import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/device_key.dart';
import '../config.dart';
import '../models.dart';
import '../offline/local_store.dart';
import 'platform_http.dart';

class ApiClient {
  ApiClient(this.config,
      {http.Client? httpClient,
      FlutterSecureStorage? storage,
      LocalStore? localStore,
      DeviceKey? deviceKey})
      : _http = httpClient ?? createPlatformHttpClient(),
        _storage = storage ?? const FlutterSecureStorage(),
        _local = localStore ?? LocalStore(),
        _deviceKey = deviceKey ?? const DeviceKey();

  final AppConfig config;
  final http.Client _http;
  final FlutterSecureStorage _storage;
  final LocalStore _local;
  final DeviceKey _deviceKey;
  bool workosUserDeletion = false;

  /// Account whose data is kept on the device; set once a session is known.
  String? _userId;

  /// The last request could not reach the server (answers come from the
  /// device then, and day edits wait in the queue).
  final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Day edits saved on the device but not yet on the server.
  final ValueNotifier<int> pendingWrites = ValueNotifier(0);

  /// Called whenever the server answers `403 consent required` (the privacy
  /// notice changed while the app was open), so any screen can recover.
  void Function()? onConsentRequired;

  Future<void> loadAuthConfig() async {
    // A failed or unavailable config response must never retain another
    // server's WorkOS deletion capability.
    workosUserDeletion = false;
    try {
      final response =
          await _send('GET', _uri('/api/auth/config'), auth: false);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          workosUserDeletion = decoded['workos_user_deletion'] == true;
        }
      }
    } catch (_) {
      workosUserDeletion = false;
    }
  }

  static const _sessionKey = 'session_token';
  static const _deviceKeyIdKey = 'device_key_id';
  static const _lastUserDoc = 'last_user';
  static const _sessionDoc = 'session';
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

  /// Signs this device out: token, device key and every local copy go.
  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
    await _forgetDevice();
    await _dropLocalData();
  }

  Future<void> _dropLocalData() async {
    _userId = null;
    pendingWrites.value = 0;
    await _local.clearAll();
  }

  Future<void> _forgetDevice() async {
    final keyId = await _storage.read(key: _deviceKeyIdKey);
    if (keyId == null) return;
    await _storage.delete(key: _deviceKeyIdKey);
    await _deviceKey.delete();
  }

  /// Signed in as [userId]: keep its data here and send what waited.
  Future<void> _remember(String userId, String sessionBody) async {
    _userId = userId;
    await _local.writeDoc(localGlobalUser, _lastUserDoc, userId);
    await _local.writeDoc(userId, _sessionDoc, sessionBody);
    await _countPending(userId);
    if (pendingWrites.value > 0) unawaited(syncPending());
  }

  /// Session snapshot from a server answer, kept for offline starts.
  Future<SessionSnapshot> _sessionFrom(http.Response response) async {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final snapshot = SessionSnapshot.fromJson(decoded);
    final user = snapshot.user;
    if (user != null) {
      // Never mix two accounts' data on the device.
      if (_userId != null && _userId != user.id) await _dropLocalData();
      decoded
        ..remove('session_token')
        ..remove('device_key_id');
      await _remember(user.id, jsonEncode(decoded));
      _role = user.role;
      await _calendarIs(user.id, user.role, snapshot.share);
    }
    return snapshot;
  }

  String? _role;

  /// Months and predictions kept here belong to one calendar: the owner's
  /// own, or the one a partner follows. When that changes (joined another
  /// owner, share revoked, role switched) the old copy goes.
  Future<void> _calendarIs(String userId, String role, ShareState? share) async {
    final calendar = role == 'partner'
        ? 'partner:${share?.status ?? 'none'}:${share?.ownerEmail ?? ''}'
        : 'own';
    final known = await _local.readDoc(userId, 'calendar');
    if (known == calendar) return;
    if (known != null) await _local.clearCalendar(userId);
    await _local.writeDoc(userId, 'calendar', calendar);
  }

  Future<ShareState> _shareChanged(ShareState share) async {
    final userId = _userId;
    final role = _role;
    if (userId != null && role != null) {
      await _calendarIs(userId, role, share);
    }
    return share;
  }

  /// The last account's session as kept on the device, while it can still
  /// talk to the server (token or device key).
  Future<SessionSnapshot?> _cachedSession() async {
    final userId = await _local.readDoc(localGlobalUser, _lastUserDoc);
    if (userId == null || userId.isEmpty) return null;
    final body = await _local.readDoc(userId, _sessionDoc);
    if (body == null) return null;
    final token = await readSessionToken();
    final keyId = await _storage.read(key: _deviceKeyIdKey);
    if ((token ?? '').isEmpty && (keyId ?? '').isEmpty) return null;
    final snapshot =
        SessionSnapshot.fromJson(jsonDecode(body) as Map<String, dynamic>);
    if (snapshot.user?.id != userId) return null;
    _userId = userId;
    _role = snapshot.user!.role;
    await _countPending(userId);
    return snapshot;
  }

  Future<void> _countPending(String userId) async {
    final count = (await _local.pendingWrites(userId)).length;
    if (_userId == userId) pendingWrites.value = count;
  }

  /// The server could not be reached (vs. it answered with an error).
  static bool _unreachable(Object err) =>
      err is! ApiException || err.statusCode >= 500 || err.statusCode == 429;

  /// [fromServer], or the device's copy when the server is out of reach.
  Future<T> _orCached<T>(
    Future<T> Function() fromServer,
    Future<T?> Function(String userId) fromCache,
  ) async {
    final userId = _userId;
    try {
      return await fromServer();
    } catch (err) {
      if (userId == null || !_unreachable(err)) rethrow;
      final cached = await fromCache(userId);
      if (cached == null) rethrow;
      return cached;
    }
  }

  Future<bool>? _renewing;

  /// Gets a new session with the device key; false when there is none or
  /// the server no longer knows it. Throws when the server cannot answer
  /// now (offline, 429, 5xx), so nothing is cleared for a passing error.
  /// One renewal at a time.
  Future<bool> _renewSession() =>
      _renewing ??= _doRenew().whenComplete(() => _renewing = null);

  Future<bool> _doRenew() async {
    final keyId = await _storage.read(key: _deviceKeyIdKey);
    if (keyId == null || keyId.isEmpty) return false;
    final challengeResponse = await _sendOnce(
      'POST',
      _uri('/api/auth/device/challenge'),
      body: {'key_id': keyId},
      auth: false,
    );
    if (challengeResponse.statusCode == 401) {
      await _forgetDevice();
      return false;
    }
    if (challengeResponse.statusCode != 200) {
      throw ApiException('device challenge', challengeResponse);
    }
    final challenge =
        (jsonDecode(challengeResponse.body) as Map)['challenge'] as String?;
    if (challenge == null) {
      throw ApiException('device challenge', challengeResponse);
    }
    // Same message the server checks (backend handler/device.go).
    final signature =
        await _deviceKey.sign('217 device session v1\n$keyId\n$challenge');
    if (signature == null) {
      // The Keystore lost the key (e.g. the screen lock was removed).
      await _forgetDevice();
      return false;
    }
    final response = await _sendOnce(
      'POST',
      _uri('/api/auth/device/session'),
      body: {'key_id': keyId, 'challenge': challenge, 'signature': signature},
      auth: false,
    );
    if (response.statusCode == 401) {
      await _forgetDevice();
      return false;
    }
    if (response.statusCode != 200) {
      throw ApiException('device session', response);
    }
    final token = (jsonDecode(response.body) as Map)['session_token'];
    if (token is! String || token.isEmpty) {
      throw ApiException('device session', response);
    }
    await saveSessionToken(token);
    return true;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      _uriFor(config.apiBaseUrl, path, query);

  static Uri _uriFor(String base, String path, [Map<String, String>? query]) {
    final uri = base.isEmpty ? Uri.parse(path) : Uri.parse('$base$path');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  /// One request; an expired session is renewed with the device key and the
  /// request sent again.
  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
  }) async {
    var response = await _sendOnce(method, uri, body: body, auth: auth);
    if (auth && response.statusCode == 401 && await _renewSession()) {
      response = await _sendOnce(method, uri, body: body, auth: auth);
    }
    if (auth &&
        response.statusCode == 403 &&
        ApiException._errorField(response.body) == 'consent required') {
      onConsentRequired?.call();
    }
    return response;
  }

  Future<http.Response> _sendOnce(
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
    final http.Response response;
    try {
      final streamed =
          await _http.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      offline.value = true;
      rethrow;
    }
    if (response.statusCode >= 502) {
      offline.value = true;
    } else if (offline.value) {
      // Back online: send what waited (the queue's own requests land here
      // too, while it runs, and are skipped).
      offline.value = false;
      if (pendingWrites.value > 0 && _syncing == null) {
        unawaited(syncPending());
      }
    }
    return response;
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

  /// The signed-in account. An expired session is renewed with the device
  /// key; out of reach, the last session kept on the device stands in.
  Future<SessionSnapshot> currentSession() async {
    http.Response response;
    try {
      response = await _send('GET', _uri('/api/auth/session'));
      if (response.statusCode == 200 &&
          (jsonDecode(response.body) as Map)['user'] == null &&
          await _renewSession()) {
        response = await _send('GET', _uri('/api/auth/session'));
      }
    } catch (err) {
      final cached = await _cachedSession();
      if (cached != null) return cached;
      rethrow;
    }
    if (response.statusCode >= 500 || response.statusCode == 429) {
      return await _cachedSession() ?? const SessionSnapshot();
    }
    if (response.statusCode != 200) {
      return const SessionSnapshot();
    }
    final snapshot = await _sessionFrom(response);
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
      // Logout only ends our session; without this AuthKit reuses its own
      // browser session and signs the user straight back in.
      'max_age': '0',
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

    // Android: a fresh Keystore key, so this sign-in lasts (see DeviceKey).
    final devicePublicKey = await _deviceKey.create();
    final response = await _send(
      'POST',
      _uri('/api/auth/workos/exchange'),
      body: {
        'code': code,
        'code_verifier': pkce.verifier,
        'redirect_uri': config.redirectUri,
        if (devicePublicKey != null) 'device_public_key': devicePublicKey,
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
    // Another account may have used this device: its data goes.
    await _dropLocalData();
    await saveSessionToken(token);
    final keyId = decoded['device_key_id'];
    if (keyId is String && keyId.isNotEmpty) {
      await _storage.write(key: _deviceKeyIdKey, value: keyId);
    } else {
      await _storage.delete(key: _deviceKeyIdKey);
      // Older server: the new key is of no use.
      if (devicePublicKey != null) await _deviceKey.delete();
    }
    await _sessionFrom(response);
    return User.fromJson(userJson);
  }

  /// Day edits still waiting are sent first when the server can be reached;
  /// signing out drops whatever could not be sent.
  Future<void> logout() async {
    try {
      if (pendingWrites.value > 0) await syncPending();
      await _send('POST', _uri('/api/auth/logout'), body: {});
    } finally {
      await clearSession();
    }
  }

  /// Records agreement to privacy notice [version] (LGPD art. 11).
  Future<SessionSnapshot> acceptConsent(int version) async {
    final response = await _send(
      'PUT',
      _uri('/api/account/consent'),
      body: {'version': version},
    );
    if (response.statusCode != 200) {
      throw ApiException('consent', response);
    }
    return _sessionFrom(response);
  }

  /// Everything the server holds about this account, as JSON text.
  Future<String> exportData() async {
    final response = await _send('GET', _uri('/api/account/export'));
    if (response.statusCode != 200) {
      throw ApiException('export', response);
    }
    return response.body;
  }

  /// Who answers privacy requests for this server (email or URL), if set.
  Future<String?> privacyContact() async {
    try {
      final response =
          await _send('GET', _uri('/api/auth/config'), auth: false);
      final decoded = jsonDecode(response.body);
      final contact = decoded is Map ? decoded['privacy_contact'] : null;
      return contact is String && contact.trim().isNotEmpty
          ? contact.trim()
          : null;
    } catch (_) {
      return null;
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
    return _shareChanged(ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>));
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
    // Accepting makes this account a partner of that owner.
    _role = 'partner';
    return _shareChanged(ShareState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>));
  }

  /// Messages the user sent or received, newest first.
  Future<List<InboxMessage>> listInbox() async {
    final response = await _send('GET', _uri('/api/inbox'));
    if (response.statusCode != 200) {
      throw ApiException('inbox', response);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['notes'] as List<dynamic>? ?? const [])
        .map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sends a message to the other person of the active share.
  Future<InboxMessage> sendMessage(String body) async {
    final response = await _send(
      'POST',
      _uri('/api/messages'),
      body: {'body': body},
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiException('message', response);
    }
    return InboxMessage.fromJson(
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
    return _sessionFrom(response);
  }

  Future<SessionSnapshot> setStage(String stage) async {
    final response =
        await _send('PUT', _uri('/api/account/stage'), body: {'stage': stage});
    if (response.statusCode != 200) throw ApiException('set stage', response);
    return _sessionFrom(response);
  }

  /// Period history and predictions for the visible calendar. [today] is the
  /// device's local date (YYYY-MM-DD).
  /// Offline, the last predictions seen on this device.
  Future<CycleInfo> getCycle(String today) => _orCached(
        () async {
          final response =
              await _send('GET', _uri('/api/cycle', {'today': today}));
          if (response.statusCode != 200) {
            throw ApiException('cycle', response);
          }
          await _keepDoc('cycle', response.body);
          return CycleInfo.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>);
        },
        (userId) async {
          final body = await _local.readDoc(userId, 'cycle');
          return body == null
              ? null
              : CycleInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
        },
      );

  /// Saves a server answer for the signed-in account.
  Future<void> _keepDoc(String key, String body) async {
    final userId = _userId;
    if (userId != null) await _local.writeDoc(userId, key, body);
  }

  Future<PartnerAlertPreference> getPartnerAlerts() => _orCached(
        () async {
          final response = await _send('GET', _uri('/api/partner-alerts'));
          if (response.statusCode != 200) {
            throw ApiException('partner alerts', response);
          }
          await _keepDoc('partner_alerts', response.body);
          return PartnerAlertPreference.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
        },
        (userId) async {
          final body = await _local.readDoc(userId, 'partner_alerts');
          return body == null
              ? null
              : PartnerAlertPreference.fromJson(
                  jsonDecode(body) as Map<String, dynamic>);
        },
      );

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
    await _keepDoc('partner_alerts', response.body);
    return PartnerAlertPreference.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// The month as the server has it, under the day edits still waiting;
  /// offline, as last seen on this device.
  Future<List<Entry>> listEntries(int year, int month) => _orCached(
        () async {
          final userId = _userId;
          final writes = _queueChanges;
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
          if (userId == null || userId != _userId) return entries;
          if (writes != _queueChanges) {
            // An edit was queued or sent meanwhile: this answer may predate
            // it. The device's copy has every edit; the next load refreshes.
            final local = await _local.monthEntries(userId, year, month);
            if (local != null) return local;
          }
          final days = {for (final e in entries) e.date: e};
          final prefix = monthPrefix(year, month);
          for (final w in await _local.pendingWrites(userId)) {
            if (!w.date.startsWith(prefix)) continue;
            if (w.entry == null) {
              days.remove(w.date);
            } else {
              days[w.date] = w.entry!;
            }
          }
          final merged = days.values.toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          await _local.replaceMonth(userId, year, month, merged);
          return merged;
        },
        (userId) => _local.monthEntries(userId, year, month),
      );

  /// Saved on the device at once and queued for the server; throws only
  /// when the server refuses the edit.
  Future<Entry> upsertEntry(
    String date, {
    bool? taken,
    String notes = '',
    bool heart = false,
    bool period = false,
  }) async {
    final entry = Entry(
      date: date,
      taken: taken,
      notes: notes,
      heart: heart,
      period: period,
    );
    final userId = _userId;
    if (userId == null) return _sendUpsert(entry);
    await _queueWrite(userId, date, entry);
    return entry;
  }

  Future<void> deleteEntry(String date) async {
    final userId = _userId;
    if (userId == null) return _sendDelete(date);
    await _queueWrite(userId, date, null);
  }

  Future<Entry> _sendUpsert(Entry entry) async {
    final response = await _send(
      'POST',
      _uri('/api/entries/${entry.date}'),
      body: {
        'taken': entry.taken,
        'notes': entry.notes,
        'heart': entry.heart,
        'period': entry.period,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('upsert entry', response);
    }
    return Entry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _sendDelete(String date) async {
    final response = await _send('DELETE', _uri('/api/entries/$date'));
    if (response.statusCode == 404) {
      return; // already cleared
    }
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException('delete entry', response);
    }
  }

  /// Edits the server refused for good, by queue ID, for whoever waits.
  final Map<int, ApiException> _refused = {};

  /// Moves whenever the queue gains or sends an edit (see listEntries).
  int _queueChanges = 0;

  Future<void> _queueWrite(String userId, String date, Entry? entry) async {
    _queueChanges++;
    await _local.putEntry(userId, date, entry);
    final queued =
        await _local.enqueue(userId, PendingWrite(date: date, entry: entry));
    await _countPending(userId);
    if (offline.value) {
      // Known to be offline: no need to wait on a request bound to fail.
      unawaited(syncPending());
      return;
    }
    await syncPending();
    final refused = _refused.remove(queued.id);
    if (refused != null) throw refused;
  }

  Future<void>? _syncing;
  bool _syncAgain = false;

  /// Sends the waiting day edits, oldest first. Stops at the first one the
  /// server cannot take now (offline, signed out, needs consent); the next
  /// edit, app resume or successful request tries again.
  Future<void> syncPending() {
    final running = _syncing;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final sync = _drainQueue();
    _syncing = sync;
    return sync.whenComplete(() => _syncing = null);
  }

  Future<void> _drainQueue() async {
    do {
      _syncAgain = false;
      final userId = _userId;
      if (userId == null) return;
      for (final write in await _local.pendingWrites(userId)) {
        // Signed out or switched account meanwhile: not this account's turn.
        if (_userId != userId) return;
        try {
          final entry = write.entry;
          if (entry == null) {
            await _sendDelete(write.date);
          } else {
            await _sendUpsert(entry);
          }
        } on ApiException catch (err) {
          // Consent fixes itself once agreed to; any other 403 (read-only
          // calendar after a role change elsewhere) is a refusal.
          final retryLater = err.statusCode == 401 ||
              (err.statusCode == 403 && err.message == 'consent required') ||
              err.statusCode == 408 ||
              err.statusCode == 429 ||
              err.statusCode >= 500;
          if (retryLater) return;
          // Refused for good: drop it; the month reloads from the server.
          _refused[write.id!] = err;
          final day = DateTime.parse(write.date);
          await _local.forgetMonth(userId, day.year, day.month);
        } catch (_) {
          return; // out of reach
        }
        _queueChanges++;
        await _local.removePending(write.id!);
        await _countPending(userId);
      }
    } while (_syncAgain);
  }

  Future<ReminderPreference?> getReminderPreference() => _orCached(
        () async {
          final response =
              await _send('GET', _uri('/api/reminders/preferences'));
          if (response.statusCode == 404) {
            await _keepDoc('reminder', 'null');
            return null;
          }
          if (response.statusCode != 200) {
            throw ApiException('reminder preference', response);
          }
          await _keepDoc('reminder', response.body);
          return ReminderPreference.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>);
        },
        (userId) async {
          final body = await _local.readDoc(userId, 'reminder');
          if (body == null || body == 'null') return null;
          return ReminderPreference.fromJson(
              jsonDecode(body) as Map<String, dynamic>);
        },
      );

  Future<ReminderPreference> upsertReminderPreference({
    required bool enabled,
    required String time,
    required String timezone,
    bool repeatEnabled = false,
    int repeatMinutes = 15,
  }) async {
    final response = await _send(
      'PUT',
      _uri('/api/reminders/preferences'),
      body: {
        'enabled': enabled,
        'time': time,
        'timezone': timezone,
        'repeat_enabled': repeatEnabled,
        'repeat_minutes': repeatMinutes,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('save reminder', response);
    }
    await _keepDoc('reminder', response.body);
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
        message = _errorField(response.body),
        consentVersion = _consentVersionField(response.body);

  final String action;
  final int statusCode;
  final String message;
  final int? consentVersion;

  static int? _consentVersionField(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['consent_version'] is num) {
        return (decoded['consent_version'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

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
