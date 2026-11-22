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
import '../secure_storage.dart';

enum SyncStatusKind { notModified, changed, unsupported }

/// Answer to [ApiClient.syncStatus]; [status] is set only when [changed].
class SyncStatusResult {
  const SyncStatusResult(this.kind, [this.status]);

  final SyncStatusKind kind;
  final SyncStatus? status;

  bool get notModified => kind == SyncStatusKind.notModified;
  bool get unsupported => kind == SyncStatusKind.unsupported;
}

class ApiClient {
  ApiClient(this.config,
      {http.Client? httpClient,
      FlutterSecureStorage? storage,
      LocalStore? localStore,
      DeviceKey? deviceKey})
      : _http = httpClient ?? createPlatformHttpClient(),
        _storage = storage ?? appSecureStorage,
        _local = localStore ?? LocalStore(),
        _deviceKey = deviceKey ?? const DeviceKey();

  final AppConfig config;
  final http.Client _http;
  final FlutterSecureStorage _storage;
  final LocalStore _local;
  final DeviceKey _deviceKey;
  bool workosUserDeletion = false;

  /// Who answers privacy requests on this server (`PRIVACY_CONTACT`: an
  /// email or URL), shown on the privacy notice; empty when unset.
  String privacyContact = '';

  /// Whether the server signs people in (AuthKit configured).
  bool authkit = false;

  /// First-party email+password sign-in (`AUTH_PASSWORD_ENABLED`).
  bool passwordAuth = false;

  /// Open sign-up for new accounts (needs [passwordAuth] too).
  bool passwordSignup = false;

  /// Address verification configured (SMTP): sign-up waits for a code.
  bool mailVerification = false;

  /// WorkOS sign-in offered (`AUTH_WORKOS_ENABLED` not false). Defaults to
  /// true: servers older than the `workos` config key (and a failed config
  /// fetch) always offered it, so only an explicit `"workos": false` hides
  /// the button.
  bool workos = true;

  /// Configured generic OIDC provider name, or null when disabled.
  String? oidcName;

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

  /// Called when a calendar response reports a different subject than the
  /// cached session expects (e.g. partner relinked on another device while
  /// `/api/auth/session` was slow), so the app refreshes the session.
  void Function()? onCalendarScopeMismatch;

  /// Called when a calendar endpoint denies access for the active calendar
  /// scope (`401`, `403 share inactive`, `403 role not chosen`, or `403
  /// calendar owner consent required`) so the mounted calendar clears its
  /// in-memory data even if another screen or a superseded load detected it.
  void Function({required bool refreshSession})? onCalendarAccessDenied;

  /// True when [loadPersistedApiBase] failed to read the saved server URL or
  /// while [setApiBaseUrl] is clearing credentials for a server switch.
  /// Authenticated requests refuse to run until the server URL is resolved so
  /// a custom server's bearer token can never be sent to a built-in default.
  bool _apiBaseUnresolved = false;
  bool get apiBaseResolved => !_apiBaseUnresolved;

  /// Moves whenever the active server changes (including resolving an
  /// unresolved server URL). Guards server-scoped public config loads without
  /// letting session clears on the same server discard valid config answers.
  int _serverEpoch = 0;

  /// Moves whenever the active server or auth lifecycle changes (sign-in,
  /// logout, server switch, session clear), invalidating in-flight probes and
  /// renewals started under an older scope.
  int _scopeEpoch = 0;
  int _authConfigGen = 0;
  int _deviceKeyGen = 0;

  /// Serializes local credential, device-key, server-URL, and session-cache
  /// mutations so interleaved probes, sign-ins, and server switches cannot
  /// corrupt each other's state. Never held across network or browser I/O.
  Future<void> _authQueue = Future<void>.value();

  Future<T> _serializeAuth<T>(Future<T> Function() action) async {
    final previous = _authQueue;
    final done = Completer<void>();
    _authQueue = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  void invalidatePendingAuth() {
    _scopeEpoch++;
    _renewing = null;
    _renewingScope = null;
    _renewingBase = null;
  }

  bool _serverChanged(int serverEpoch, String base) =>
      serverEpoch != _serverEpoch || base != config.apiBaseUrl;

  bool _scopeChanged(int scope, String base) =>
      scope != _scopeEpoch || base != config.apiBaseUrl;

  Future<void> loadAuthConfig() async {
    final serverEpoch = _serverEpoch;
    final base = config.apiBaseUrl;
    final gen = ++_authConfigGen;
    // A failed or unavailable config response must never retain another
    // server's WorkOS deletion capability.
    workosUserDeletion = false;
    privacyContact = '';
    authkit = false;
    passwordAuth = false;
    passwordSignup = false;
    mailVerification = false;
    workos = true;
    oidcName = null;
    try {
      final response = await _send(
        'GET',
        _uriFor(base, '/api/auth/config'),
        auth: false,
        expectedServerEpoch: serverEpoch,
        expectedBase: base,
      );
      if (_serverChanged(serverEpoch, base) || gen != _authConfigGen) return;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          workosUserDeletion = decoded['workos_user_deletion'] == true;
          authkit = decoded['authkit'] == true;
          passwordAuth = decoded['password'] == true;
          passwordSignup = decoded['signup'] == true;
          mailVerification = decoded['mail'] == true;
          // Absent key: an older server, which always offered WorkOS.
          workos = decoded['workos'] != false && decoded['authkit'] != false;
          final oidc = decoded['oidc'];
          final name = oidc is Map ? oidc['name'] : null;
          oidcName = name is String && name.trim().isNotEmpty ? name : null;
          final contact = decoded['privacy_contact'];
          privacyContact = contact is String ? contact.trim() : '';
        }
      }
    } catch (_) {
      if (_serverChanged(serverEpoch, base) || gen != _authConfigGen) return;
      workosUserDeletion = false;
    }
  }

  static const _sessionKey = 'session_token';
  static const _deviceKeyIdKey = 'device_key_id';
  static const _lastUserDoc = 'last_user';
  static const _sessionDoc = 'session';
  static const _apiBaseKey = 'api_base_url';
  static const _calendarInvalidatedKey = 'calendar_invalidated_user';
  static const _invalidatedCalendarMarker = 'invalidated';
  static const _consentBlockedKey = 'consent_blocked_user';

  /// Loads the persisted server URL override, if any. Returns false when
  /// reading storage failed (distinct from "no override saved") and blocks
  /// authenticated requests until resolved. Serialized with [setApiBaseUrl]
  /// so a reload cannot restore an older URL over a completed server switch.
  Future<bool> loadPersistedApiBase() {
    final serverEpoch = _serverEpoch;
    return _serializeAuth(() async {
      if (serverEpoch != _serverEpoch) return !_apiBaseUnresolved;
      try {
        final saved =
            normalizeApiBase(await _storage.read(key: _apiBaseKey) ?? '');
        config.apiBaseUrl = saved.isEmpty ? config.defaultApiBaseUrl : saved;
        _apiBaseUnresolved = false;
        return true;
      } catch (_) {
        _apiBaseUnresolved = true;
        _userId = null;
        _role = null;
        return false;
      }
    });
  }

  /// The server in use and its session token as saved on this device, read
  /// without side effects (for background work, which must never renew or
  /// clear the app's session).
  static Future<({String server, String? token})> storedLogin(
    AppConfig config,
    FlutterSecureStorage storage,
  ) async {
    final saved = normalizeApiBase(await storage.read(key: _apiBaseKey) ?? '');
    // Missing or empty (older builds stored '' for same-origin) → build default.
    return (
      server: saved.isEmpty ? config.defaultApiBaseUrl : saved,
      token: await storage.read(key: _sessionKey),
    );
  }

  /// Validates a self-hosted server URL; empty means "use the default server".
  /// A bare host gets `https://`, and a pasted invite link
  /// (`https://host/app/?invite=CODE`) or web app address keeps only its
  /// server part: the web app lives under `/app/`, the API beside it.
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
      path: uri.path.replaceFirst(RegExp(r'/app(/.*)?$'), ''),
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
  /// Returns true when the server changed (or when resolving a previously
  /// unreadable server URL). Authenticated requests stay blocked during the
  /// transition and old credentials are removed before publishing the new URL.
  Future<bool> setApiBaseUrl(String value) async {
    final parsed = parseApiBase(value);
    final next = parsed.isEmpty ? config.defaultApiBaseUrl : parsed;
    return _serializeAuth(() async {
      final wasUnresolved = _apiBaseUnresolved;
      final changed = wasUnresolved || next != config.apiBaseUrl;
      if (!changed) {
        if (next == config.defaultApiBaseUrl) {
          await _storage.delete(key: _apiBaseKey);
        }
        return false;
      }
      _apiBaseUnresolved = true;
      _serverEpoch++;
      invalidatePendingAuth();
      await _clearSessionLocked();
      if (next == config.defaultApiBaseUrl) {
        await _storage.delete(key: _apiBaseKey);
      } else {
        await _storage.write(key: _apiBaseKey, value: next);
      }
      config.apiBaseUrl = next;
      _apiBaseUnresolved = false;
      // Bump again on completion so any loadPersistedApiBase() or probe queued
      // during cleanup cannot overwrite the newly published server state.
      _serverEpoch++;
      invalidatePendingAuth();
      return true;
    });
  }

  Future<String?> readSessionToken() => _storage.read(key: _sessionKey);

  Future<void> saveSessionToken(String token) =>
      _storage.write(key: _sessionKey, value: token);

  /// Signs this device out: token, device key and every local copy go.
  Future<void> clearSession() => _serializeAuth(() async {
        invalidatePendingAuth();
        await _clearSessionLocked();
        invalidatePendingAuth();
      });

  Future<void> _clearSessionInScope(int expectedScope, String expectedBase,
          {int? expectedSessionRevision}) =>
      _serializeAuth(() async {
        if (_scopeChanged(expectedScope, expectedBase) ||
            (expectedSessionRevision != null &&
                expectedSessionRevision != _sessionRevision)) {
          throw const StaleAuthScopeException();
        }
        invalidatePendingAuth();
        await _clearSessionLocked();
        invalidatePendingAuth();
      });

  Future<void> _clearSessionLocked() async {
    await _storage.delete(key: _sessionKey);
    await _forgetDeviceLocked();
    await _dropLocalDataLocked();
  }

  Future<void> _dropLocalDataLocked() async {
    _userId = null;
    _role = null;
    _calendarSubjectId = null;
    _calendarGeneration++;
    _sessionRevision++;
    _consentRevision++;
    _mutationRevision++;
    pendingWrites.value = 0;
    await _local.clearAll();
    _calendarCacheBlocked = false;
    _consentBlocked = false;
    _consentBlockedVersion = null;
    try {
      await _storage.delete(key: _calendarInvalidatedKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _consentBlockedKey);
    } catch (_) {}
  }

  Future<void> _forgetDeviceLocked() async {
    _deviceKeyGen++;
    final keyId = await _storage.read(key: _deviceKeyIdKey);
    if (keyId == null) return;
    await _storage.delete(key: _deviceKeyIdKey);
    await _deviceKey.delete();
  }

  /// Signed in as [userId]: keep its data here and return whether queued edits
  /// should be synced after releasing the auth lock.
  Future<bool> _rememberLocked(String userId, String sessionBody) async {
    _userId = userId;
    await _local.writeDoc(localGlobalUser, _lastUserDoc, userId);
    await _local.writeDoc(userId, _sessionDoc, sessionBody);
    await _countPending(userId);
    return pendingWrites.value > 0;
  }

  /// Session snapshot from a server answer, kept for offline starts.
  Future<SessionSnapshot> _sessionFrom(
    http.Response response, {
    int? expectedScope,
    String? expectedBase,
    int? expectedSessionRevision,
    int? expectedMutationRevision,
    bool consentGranted = false,
  }) async {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final snapshot = SessionSnapshot.fromJson(decoded);
    var shouldSync = false;
    await _serializeAuth(() async {
      if (expectedScope != null &&
          _scopeChanged(expectedScope, expectedBase ?? config.apiBaseUrl)) {
        throw const StaleAuthScopeException();
      }
      if ((expectedSessionRevision != null &&
              expectedSessionRevision != _sessionRevision) ||
          (expectedMutationRevision != null &&
              expectedMutationRevision != _mutationRevision)) {
        throw const StaleAuthScopeException();
      }
      shouldSync = await _applySessionLocked(
        decoded,
        snapshot,
        consentGranted: consentGranted,
      );
    });
    if (shouldSync) unawaited(syncPending());
    return snapshot;
  }

  Future<bool> _applySessionLocked(
    Map<String, dynamic> decoded,
    SessionSnapshot snapshot, {
    bool consentGranted = false,
  }) async {
    final user = snapshot.user;
    if (user == null) return false;
    if (snapshot.consentRequired) {
      // Apply a confirmed consent denial in memory before any disk I/O and
      // fall back to secure storage if persisting the session doc fails, so a
      // local write error can never fail open and leave cached rows visible.
      if (_userId != null && _userId != user.id) {
        try {
          await _dropLocalDataLocked();
        } catch (_) {
          _calendarCacheBlocked = true;
        }
      }
      _userId = user.id;
      _role = user.role;
      _consentBlocked = true;
      _consentBlockedVersion =
          snapshot.consentVersion > 0 ? snapshot.consentVersion : null;
      _calendarGeneration++;
      _sessionRevision++;
      _mutationRevision++;
      try {
        await _calendarIs(user.id, user.role, snapshot.share);
      } catch (_) {
        await _markCalendarInvalidatedLocked(user.id);
      }
      decoded
        ..remove('session_token')
        ..remove('device_key_id');
      try {
        await _rememberLocked(user.id, jsonEncode(decoded));
        await _clearConsentBlockedFallbackLocked(user.id);
      } catch (_) {
        await _markConsentBlockedFallbackLocked(
          user.id,
          snapshot.consentVersion,
        );
      }
      return false;
    }
    // Never mix two accounts' data on the device.
    if (_userId != null && _userId != user.id) await _dropLocalDataLocked();
    // Invalidate any previous calendar before persisting the new session so a
    // crash between writes cannot pair the new session with the old owner's
    // cached months or cycle predictions.
    await _calendarIs(user.id, user.role, snapshot.share);
    decoded
      ..remove('session_token')
      ..remove('device_key_id');
    final shouldSync = await _rememberLocked(user.id, jsonEncode(decoded));
    final wasConsentBlocked = _consentBlocked;
    _role = user.role;
    _consentBlocked = false;
    _consentBlockedVersion = null;
    await _clearConsentBlockedFallbackLocked(user.id);
    _sessionRevision++;
    // Only invalidate in-flight 403s when consent was explicitly granted or
    // cleared a prior consent block; a routine session refresh from before
    // consent was withdrawn must not cause a newer 403 to be discarded.
    if (wasConsentBlocked || consentGranted) {
      _consentRevision++;
    }
    return shouldSync;
  }

  String? _role;
  String? _calendarSubjectId;

  /// True when a calendar invalidation failed to delete local rows from disk;
  /// suppresses local calendar cache reads until a subsequent clear succeeds.
  bool _calendarCacheBlocked = false;

  /// True after an explicit `403 consent required` (or a cached session with
  /// `consentRequired == true`); suppresses local calendar cache reads and
  /// outbox sync until the server confirms consent again, while preserving
  /// local rows on disk.
  bool _consentBlocked = false;
  int? _consentBlockedVersion;

  bool get _calendarReadBlocked => _calendarCacheBlocked || _consentBlocked;

  /// Moves whenever the calendar kept on the device is cleared or changes.
  int _calendarGeneration = 0;

  /// Moves whenever a server session, share mutation, consent block, or
  /// calendar invalidation commits, so an in-flight session response or offline
  /// fallback cannot roll back a newer session, consent block, or share state.
  int _sessionRevision = 0;

  // Unlike session refreshes, these changes invalidate pending mutations.
  int _mutationRevision = 0;

  /// Moves whenever consent is explicitly granted or transitions from blocked
  /// to confirmed, so a late `403 consent required` from before consent was
  /// granted cannot re-persist the block without discarding denials raced with
  /// routine session refreshes.
  int _consentRevision = 0;

  static String _calendarMarker(String role, ShareState? share) {
    if (role != 'partner') return 'own';
    final ownerId = share?.ownerId ?? '';
    final ownerSuffix = ownerId.isNotEmpty
        ? '$ownerId:${share?.ownerEmail ?? ''}'
        : (share?.ownerEmail ?? '');
    return 'partner:${share?.status ?? 'none'}:$ownerSuffix';
  }

  Future<void> _markConsentBlockedFallbackLocked(
    String userId,
    int? version,
  ) async {
    try {
      await _storage.write(
        key: _consentBlockedKey,
        value: '$userId:${version ?? 0}',
      );
    } catch (_) {}
  }

  Future<void> _clearConsentBlockedFallbackLocked(String userId) async {
    try {
      final raw = await _storage.read(key: _consentBlockedKey);
      if (raw != null && raw.startsWith('$userId:')) {
        await _storage.delete(key: _consentBlockedKey);
      }
    } catch (_) {}
  }

  Future<void> _markCalendarInvalidatedLocked(String userId) async {
    _calendarCacheBlocked = true;
    try {
      await _local.writeDoc(userId, 'calendar', _invalidatedCalendarMarker);
    } catch (_) {}
    try {
      await _storage.write(key: _calendarInvalidatedKey, value: userId);
    } catch (_) {}
  }

  Future<void> _clearCalendarOrPersistInvalidationLocked(String userId) async {
    try {
      await _local.clearCalendar(userId);
      _calendarCacheBlocked = false;
      try {
        if (await _storage.read(key: _calendarInvalidatedKey) == userId) {
          await _storage.delete(key: _calendarInvalidatedKey);
        }
      } catch (_) {}
    } catch (_) {
      await _markCalendarInvalidatedLocked(userId);
    }
  }

  /// Months and predictions kept here belong to one calendar: the owner's
  /// own, or the one a partner follows. When that changes (joined another
  /// owner, share revoked, role switched) the old copy goes.
  Future<void> _calendarIs(String userId, String role, ShareState? share) async {
    _calendarSubjectId = role == 'partner'
        ? (share?.isActive == true && share!.ownerId.isNotEmpty
            ? share.ownerId
            : null)
        : (role == 'owner' ? userId : null);
    final calendar = _calendarMarker(role, share);
    final known = await _local.readDoc(userId, 'calendar');
    var invalidatedInStorage = false;
    try {
      invalidatedInStorage =
          await _storage.read(key: _calendarInvalidatedKey) == userId;
    } catch (_) {}
    if (known == calendar && !_calendarCacheBlocked && !invalidatedInStorage) {
      return;
    }
    _calendarGeneration++;
    _mutationRevision++;
    if (known != null ||
        role == 'partner' ||
        _calendarCacheBlocked ||
        invalidatedInStorage) {
      try {
        await _local.clearCalendar(userId);
        _calendarCacheBlocked = false;
        if (invalidatedInStorage) {
          try {
            await _storage.delete(key: _calendarInvalidatedKey);
          } catch (_) {}
        }
      } catch (_) {
        await _markCalendarInvalidatedLocked(userId);
        return;
      }
    }
    await _local.writeDoc(userId, 'calendar', calendar);
  }

  Future<ShareState> _shareChanged(
    ShareState share, {
    required int expectedScope,
    required String expectedBase,
    String? newRole,
  }) async {
    await _serializeAuth(() async {
      if (_scopeChanged(expectedScope, expectedBase)) {
        throw const StaleAuthScopeException();
      }
      if (newRole != null) _role = newRole;
      final userId = _userId;
      final role = _role;
      if (userId != null && role != null) {
        // Invalidate the previous calendar strictly before persisting the
        // updated share/role into the cached session doc so a follow-up
        // offline session refresh never rolls back the confirmed mutation.
        await _calendarIs(userId, role, share);
        final raw = await _local.readDoc(userId, _sessionDoc);
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              decoded['share'] = share.toJson();
              if (newRole != null && decoded['user'] is Map) {
                (decoded['user'] as Map)['role'] = newRole;
              }
              await _local.writeDoc(userId, _sessionDoc, jsonEncode(decoded));
            }
          } catch (_) {}
        }
        _sessionRevision++;
        _mutationRevision++;
      }
    });
    return share;
  }

  /// The last account's session as kept on the device, while it can still
  /// talk to the server (token or device key).
  Future<SessionSnapshot?> cachedSession() async {
    final scope = _scopeEpoch;
    final serverEpoch = _serverEpoch;
    return _adoptCachedSession(
      expectedScope: scope,
      expectedServerEpoch: serverEpoch,
      throwOnStale: false,
    );
  }

  /// Reads the cached session from local storage without mutating any client
  /// fields; callers must validate their scope before adopting the result.
  Future<
      ({
        String userId,
        SessionSnapshot snapshot,
        bool consentBlockedInStorage,
        bool consentBlockedReadFailed,
        int? consentBlockedVersion,
      })?> _readCachedSession() async {
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
    var consentBlockedInStorage = false;
    var consentBlockedReadFailed = false;
    int? consentBlockedVersion;
    try {
      final rawBlocked = await _storage.read(key: _consentBlockedKey);
      if (rawBlocked != null && rawBlocked.startsWith('$userId:')) {
        consentBlockedInStorage = true;
        final parsed = int.tryParse(rawBlocked.substring(userId.length + 1));
        if (parsed != null && parsed > 0) consentBlockedVersion = parsed;
      }
    } catch (_) {
      consentBlockedReadFailed = true;
    }
    // A kept session is never a recent sign-in.
    return (
      userId: userId,
      snapshot: SessionSnapshot(
        user: snapshot.user,
        share: snapshot.share,
        consentRequired: snapshot.consentRequired,
        consentVersion: snapshot.consentVersion,
        fromCache: true,
      ),
      consentBlockedInStorage: consentBlockedInStorage,
      consentBlockedReadFailed: consentBlockedReadFailed,
      consentBlockedVersion: consentBlockedVersion,
    );
  }

  Future<SessionSnapshot?> _adoptCachedSession({
    required int expectedScope,
    int? expectedServerEpoch,
    String? expectedBase,
    int? expectedSessionRevision,
    required bool throwOnStale,
  }) async {
    final readRevision = expectedSessionRevision ?? _sessionRevision;
    final readCalendarGen = _calendarGeneration;
    final cached = await _readCachedSession();
    return _serializeAuth(() async {
      final stale = expectedBase != null
          ? _scopeChanged(expectedScope, expectedBase)
          : expectedScope != _scopeEpoch ||
              (expectedServerEpoch != null &&
                  expectedServerEpoch != _serverEpoch) ||
              _apiBaseUnresolved;
      if (stale ||
          readRevision != _sessionRevision ||
          readCalendarGen != _calendarGeneration) {
        if (throwOnStale) throw const StaleAuthScopeException();
        return null;
      }
      if (cached == null) return null;
      final inMemoryBlocked = _userId == cached.userId && _consentBlocked;
      // If the consent-block fallback marker could not be read from secure
      // storage, never adopt a cached snapshot that claims consent (unless
      // this client already holds the consent block in memory).
      if (cached.consentBlockedReadFailed &&
          !cached.snapshot.consentRequired &&
          !inMemoryBlocked) {
        return null;
      }
      await _calendarIs(
        cached.userId,
        cached.snapshot.user!.role,
        cached.snapshot.share,
      );
      final effectiveConsentRequired = cached.snapshot.consentRequired ||
          cached.consentBlockedInStorage ||
          inMemoryBlocked;
      final effectiveConsentVersion = effectiveConsentRequired
          ? ((inMemoryBlocked ? _consentBlockedVersion : null) ??
              cached.consentBlockedVersion ??
              cached.snapshot.consentVersion)
          : cached.snapshot.consentVersion;
      _userId = cached.userId;
      _role = cached.snapshot.user!.role;
      _consentBlocked = effectiveConsentRequired;
      _consentBlockedVersion =
          effectiveConsentRequired && effectiveConsentVersion > 0
              ? effectiveConsentVersion
              : null;
      await _countPending(cached.userId);
      if (effectiveConsentRequired && !cached.snapshot.consentRequired) {
        return SessionSnapshot(
          user: cached.snapshot.user,
          share: cached.snapshot.share,
          consentRequired: true,
          consentVersion: effectiveConsentVersion,
          fromCache: true,
        );
      }
      return cached.snapshot;
    });
  }

  Future<void> _countPending(String userId) async {
    final count = (await _local.pendingWrites(userId)).length;
    if (_userId == userId) pendingWrites.value = count;
  }

  /// The server could not be reached (vs. it answered with an error).
  static bool _unreachable(Object err) =>
      err is! CalendarScopeMismatchException &&
      err is! StaleAuthScopeException &&
      (err is! ApiException || err.statusCode >= 500 || err.statusCode == 429);

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
  int? _renewingScope;
  String? _renewingBase;

  /// Gets a new session with the device key; false when there is none or
  /// the server no longer knows it. Throws when the server cannot answer
  /// now (offline, 429, 5xx), so nothing is cleared for a passing error.
  /// One renewal at a time per auth scope.
  Future<bool> _renewSession({int? expectedScope, String? expectedBase}) {
    final scope = expectedScope ?? _scopeEpoch;
    final base = expectedBase ?? config.apiBaseUrl;
    if (_scopeChanged(scope, base)) return Future.value(false);
    if (_renewing != null &&
        _renewingScope == scope &&
        _renewingBase == base) {
      return _renewing!;
    }
    _renewingScope = scope;
    _renewingBase = base;
    late final Future<bool> run;
    run = _doRenew(scope, base).whenComplete(() {
      if (identical(_renewing, run)) {
        _renewing = null;
        _renewingScope = null;
        _renewingBase = null;
      }
    });
    return _renewing = run;
  }

  Future<void> _forgetDeviceInScope(int scope, String base) =>
      _serializeAuth(() async {
        if (_scopeChanged(scope, base)) return;
        await _forgetDeviceLocked();
      });

  Future<bool> _doRenew(int scope, String base) async {
    final keyId = await _serializeAuth(() async {
      if (_scopeChanged(scope, base)) return null;
      return _storage.read(key: _deviceKeyIdKey);
    });
    if (_scopeChanged(scope, base) || keyId == null || keyId.isEmpty) {
      return false;
    }
    final challengeResponse = await _sendOnce(
      'POST',
      _uriFor(base, '/api/auth/device/challenge'),
      body: {'key_id': keyId},
      auth: false,
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) return false;
    if (challengeResponse.statusCode == 401) {
      await _forgetDeviceInScope(scope, base);
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
    if (_scopeChanged(scope, base)) return false;
    if (signature == null) {
      // The Keystore lost the key (e.g. the screen lock was removed).
      await _forgetDeviceInScope(scope, base);
      return false;
    }
    final response = await _sendOnce(
      'POST',
      _uriFor(base, '/api/auth/device/session'),
      body: {'key_id': keyId, 'challenge': challenge, 'signature': signature},
      auth: false,
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) return false;
    if (response.statusCode == 401) {
      await _forgetDeviceInScope(scope, base);
      return false;
    }
    if (response.statusCode != 200) {
      throw ApiException('device session', response);
    }
    final token = (jsonDecode(response.body) as Map)['session_token'];
    if (token is! String || token.isEmpty) {
      throw ApiException('device session', response);
    }
    return _serializeAuth(() async {
      if (_scopeChanged(scope, base)) return false;
      await saveSessionToken(token);
      return true;
    });
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
    Map<String, String>? headers,
    int? expectedScope,
    int? expectedServerEpoch,
    String? expectedBase,
  }) async {
    final scope = expectedScope ?? (auth ? _scopeEpoch : null);
    final serverEpoch = expectedServerEpoch ?? _serverEpoch;
    final base = expectedBase ?? config.apiBaseUrl;
    final consentRev = _consentRevision;
    bool isStale() => scope != null
        ? _scopeChanged(scope, base)
        : _serverChanged(serverEpoch, base);
    var response = await _sendOnce(
      method,
      uri,
      body: body,
      auth: auth,
      headers: headers,
      expectedScope: scope,
      expectedServerEpoch: serverEpoch,
      expectedBase: base,
    );
    if (isStale()) return response;
    if (auth &&
        response.statusCode == 401 &&
        await _renewSession(expectedScope: scope, expectedBase: base)) {
      if (isStale()) return response;
      response = await _sendOnce(
        method,
        uri,
        body: body,
        auth: auth,
        headers: headers,
        expectedScope: scope,
        expectedServerEpoch: serverEpoch,
        expectedBase: base,
      );
    }
    if (isStale()) return response;
    if (auth &&
        response.statusCode == 403 &&
        ApiException._errorField(response.body) == 'consent required') {
      final applied = await _persistConsentRequired(
        expectedScope: scope,
        expectedBase: base,
        expectedConsentRev: consentRev,
        consentVersion: ApiException._consentVersionField(response.body),
      );
      if (applied) onConsentRequired?.call();
    }
    return response;
  }

  /// Marks the cached session as requiring consent so an offline restart after
  /// `403 consent required` keeps private calendar rows blocked until consent
  /// is confirmed again, without deleting the underlying local entries.
  /// Returns false when the 403 belongs to a stale auth/consent revision or
  /// repeats an already-active block for the same consent version.
  Future<bool> _persistConsentRequired({
    int? expectedScope,
    required String expectedBase,
    required int expectedConsentRev,
    int? consentVersion,
  }) =>
      _serializeAuth(() async {
        if (expectedScope != null &&
            _scopeChanged(expectedScope, expectedBase)) {
          return false;
        }
        if (expectedConsentRev != _consentRevision) return false;
        _mutationRevision++;
        final wasBlocked = _consentBlocked;
        final prevBlockedVersion = _consentBlockedVersion;
        _consentBlocked = true;
        if (consentVersion != null && consentVersion > 0) {
          _consentBlockedVersion = consentVersion;
        }
        final userId = _userId;
        final versionChanged = consentVersion != null &&
            consentVersion > 0 &&
            consentVersion != prevBlockedVersion;
        if (userId == null) {
          final newlyBlocked = !wasBlocked || versionChanged;
          if (newlyBlocked) {
            _calendarGeneration++;
            _sessionRevision++;
          }
          return newlyBlocked;
        }
        try {
          final raw = await _local.readDoc(userId, _sessionDoc);
          if (raw == null) {
            final newlyBlocked = !wasBlocked || versionChanged;
            if (newlyBlocked) {
              _calendarGeneration++;
              _sessionRevision++;
            }
            await _markConsentBlockedFallbackLocked(userId, consentVersion);
            return newlyBlocked;
          }
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            final newlyBlocked = !wasBlocked || versionChanged;
            if (newlyBlocked) {
              _calendarGeneration++;
              _sessionRevision++;
            }
            await _markConsentBlockedFallbackLocked(userId, consentVersion);
            return newlyBlocked;
          }
          final prevConsent = decoded['consent'];
          final prevRequired =
              prevConsent is Map && prevConsent['required'] == true;
          final prevVersion =
              prevConsent is Map && prevConsent['version'] is num
                  ? (prevConsent['version'] as num).toInt()
                  : 0;
          final nextVersion = consentVersion ?? prevVersion;
          if (nextVersion > 0) _consentBlockedVersion = nextVersion;
          final newlyBlocked = !wasBlocked ||
              (consentVersion != null &&
                  consentVersion > 0 &&
                  consentVersion != (prevBlockedVersion ?? prevVersion));
          if (prevRequired && prevVersion == nextVersion) {
            return newlyBlocked;
          }
          decoded['consent'] = {
            'version': nextVersion,
            'required': true,
          };
          if (newlyBlocked) {
            _calendarGeneration++;
            _sessionRevision++;
          }
          try {
            await _local.writeDoc(userId, _sessionDoc, jsonEncode(decoded));
            await _clearConsentBlockedFallbackLocked(userId);
          } catch (_) {
            await _markConsentBlockedFallbackLocked(userId, nextVersion);
          }
          return newlyBlocked;
        } catch (_) {
          // Still advance revisions so a delayed 200 session cannot overwrite
          // this denial, and never turn a 403 into a storage/offline error.
          final newlyBlocked = !wasBlocked || versionChanged;
          if (newlyBlocked) {
            _calendarGeneration++;
            _sessionRevision++;
          }
          await _markConsentBlockedFallbackLocked(userId, consentVersion);
          return newlyBlocked;
        }
      });

  Future<http.Response> _sendOnce(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
    Map<String, String>? headers,
    int? expectedScope,
    int? expectedServerEpoch,
    String? expectedBase,
  }) async {
    final scope = expectedScope ?? (auth ? _scopeEpoch : null);
    final serverEpoch = expectedServerEpoch ?? _serverEpoch;
    final base = expectedBase ?? config.apiBaseUrl;
    bool isStale() => scope != null
        ? _scopeChanged(scope, base)
        : _serverChanged(serverEpoch, base);
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };
    if (auth) {
      final token = await _serializeAuth(() async {
        if (_apiBaseUnresolved) {
          throw StateError('server URL could not be read from storage');
        }
        if (isStale()) {
          throw const StaleAuthScopeException();
        }
        return readSessionToken();
      });
      if (token != null && token.isNotEmpty) {
        requestHeaders['Authorization'] = 'Bearer $token';
      }
    }
    final request = http.Request(method, uri)..headers.addAll(requestHeaders);
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      if (!isStale()) offline.value = true;
      rethrow;
    }
    if (isStale()) return response;
    if (response.statusCode >= 502) {
      offline.value = true;
    } else if (offline.value) {
      // Back online: send what waited (the queue's own requests land here
      // too, while it runs, and are skipped).
      offline.value = false;
      if (pendingWrites.value > 0 && _syncing == null && !_consentBlocked) {
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
      return decoded['authkit'] == true ||
              decoded['password'] == true ||
              decoded['oidc'] is Map
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
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final startRevision = _sessionRevision;
    http.Response response;
    try {
      response = await _send(
        'GET',
        _uriFor(base, '/api/auth/session'),
        expectedScope: scope,
        expectedBase: base,
      );
      if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
      if (response.statusCode == 200 &&
          (jsonDecode(response.body) as Map)['user'] == null &&
          await _renewSession(expectedScope: scope, expectedBase: base)) {
        if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
        response = await _send(
          'GET',
          _uriFor(base, '/api/auth/session'),
          expectedScope: scope,
          expectedBase: base,
        );
      }
    } catch (err) {
      if (err is StaleAuthScopeException || _scopeChanged(scope, base)) {
        throw const StaleAuthScopeException();
      }
      final cached = await _adoptCachedSession(
        expectedScope: scope,
        expectedBase: base,
        expectedSessionRevision: startRevision,
        throwOnStale: true,
      );
      if (cached != null) return cached;
      rethrow;
    }
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    if (response.statusCode == 401) {
      await _clearSessionInScope(scope, base,
          expectedSessionRevision: startRevision);
      return const SessionSnapshot();
    }
    if (response.statusCode != 200) {
      return await _adoptCachedSession(
            expectedScope: scope,
            expectedBase: base,
            expectedSessionRevision: startRevision,
            throwOnStale: true,
          ) ??
          const SessionSnapshot(fromCache: true);
    }
    final snapshot = await _sessionFrom(
      response,
      expectedScope: scope,
      expectedBase: base,
      expectedSessionRevision: startRevision,
    );
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    if (snapshot.user == null) {
      await _clearSessionInScope(scope, base);
    }
    return snapshot;
  }

  Future<User> signInWithWorkOS() async {
    invalidatePendingAuth();
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final clientId = await signInClientId();
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
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
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    final returned = Uri.parse(result);
    final code = returned.queryParameters['code'];
    final state = returned.queryParameters['state'];
    if (code == null || code.isEmpty) {
      throw StateError('WorkOS callback missing authorization code');
    }
    if (state != pkce.state) {
      throw StateError('WorkOS callback state mismatch');
    }

    return _exchangeSignIn(scope, base, '/api/auth/workos/exchange', {
      'code': code,
      'code_verifier': pkce.verifier,
      'redirect_uri': config.redirectUri,
    });
  }

  Future<User> signInWithOIDC() async {
    invalidatePendingAuth();
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final pkce = _Pkce.generate();
    final url = _uriFor(base, '/api/auth/oidc/native',
        {'app_challenge': pkce.challenge});
    final result = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: 'com.caldasstudios.app217',
      options: const FlutterWebAuth2Options(useWebview: false),
    );
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    final returned = Uri.parse(result);
    final error = returned.queryParameters['error'];
    if (error != null) throw OIDCSignInException(error);
    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const OIDCSignInException('oidc_failed');
    }
    return _exchangeSignIn(scope, base, '/api/auth/oidc/exchange', {
      'code': code,
      'code_verifier': pkce.verifier,
    });
  }

  Future<User> _exchangeSignIn(
      int scope, String base, String path, Map<String, String> body) async {
    // Android: a fresh Keystore key, so this sign-in lasts (see DeviceKey).
    int? keyGen;
    final devicePublicKey = await _serializeAuth(() async {
      if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
      keyGen = ++_deviceKeyGen;
      return _deviceKey.create();
    });
    Future<void> deleteOwnedDeviceKey() => _serializeAuth(() async {
          if (devicePublicKey != null && keyGen == _deviceKeyGen) {
            await _deviceKey.delete();
          }
        });
    final response = await _send(
      'POST',
      _uriFor(base, path),
      body: {
        ...body,
        if (devicePublicKey != null) 'device_public_key': devicePublicKey,
      },
      auth: false,
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) {
      await deleteOwnedDeviceKey();
      throw const StaleAuthScopeException();
    }
    if (response.statusCode != 200) {
      await deleteOwnedDeviceKey();
      throw StateError(
          'WorkOS exchange failed (${response.statusCode}): ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['session_token'] as String?;
    final userJson = decoded['user'] as Map<String, dynamic>?;
    if (token == null || userJson == null) {
      await deleteOwnedDeviceKey();
      throw StateError('WorkOS exchange response missing session');
    }
    final snapshot = SessionSnapshot.fromJson(decoded);
    var shouldSync = false;
    await _serializeAuth(() async {
      if (_scopeChanged(scope, base)) {
        if (devicePublicKey != null && keyGen == _deviceKeyGen) {
          await _deviceKey.delete();
        }
        throw const StaleAuthScopeException();
      }
      // Invalidate probes started before commit and bump again once credentials
      // and local session cache are written so probes started during commit
      // cannot observe old storage under the post-commit scope.
      invalidatePendingAuth();
      // Another account may have used this device: its data goes.
      await _dropLocalDataLocked();
      await saveSessionToken(token);
      final keyId = decoded['device_key_id'];
      if (keyId is String && keyId.isNotEmpty) {
        await _storage.write(key: _deviceKeyIdKey, value: keyId);
      } else {
        await _storage.delete(key: _deviceKeyIdKey);
        // Older server: the new key is of no use.
        if (devicePublicKey != null && keyGen == _deviceKeyGen) {
          await _deviceKey.delete();
        }
      }
      shouldSync = await _applySessionLocked(decoded, snapshot);
      invalidatePendingAuth();
    });
    if (shouldSync) unawaited(syncPending());
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

  Future<SessionSnapshot> _sendSession(
    String method,
    String path, {
    Object? body,
    required String errorContext,
    bool consentGranted = false,
    bool consentWithdrawn = false,
  }) async {
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final startRevision = _mutationRevision;
    final response = await _send(
      method,
      _uriFor(base, path),
      body: body,
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    if (response.statusCode != 200) {
      throw ApiException(errorContext, response);
    }
    return _sessionFrom(
      response,
      expectedScope: scope,
      expectedBase: base,
      expectedMutationRevision: consentWithdrawn ? null : startRevision,
      consentGranted: consentGranted,
    );
  }

  /// Records agreement to privacy notice [version] (LGPD art. 11).
  Future<SessionSnapshot> acceptConsent(int version) => _sendSession(
        'PUT',
        '/api/account/consent',
        body: {'version': version},
        errorContext: 'consent',
        consentGranted: true,
      );

  /// The web app's privacy notice in [language] (`en`, `pt`, `es`) on this
  /// server, where people download or delete their data and withdraw
  /// consent; with [deleteAccount], the account deletion page instead.
  String privacyPageUrl(String language, {bool deleteAccount = false}) {
    final uri = _uri(
      deleteAccount ? accountDeletePagePath : privacyPagePath,
      {'lang': language},
    );
    return uri.hasScheme ? uri.toString() : Uri.base.resolveUri(uri).toString();
  }

  /// Withdraws consent: the data stays, but the server stops processing it
  /// until the notice is agreed to again.
  Future<SessionSnapshot> withdrawConsent() => _sendSession(
        'DELETE',
        '/api/account/consent',
        errorContext: 'withdraw consent',
        consentWithdrawn: true,
      );

  /// Everything the server holds about the caller: the file name the server
  /// suggests and the JSON bytes.
  Future<({String fileName, List<int> bytes})> exportAccount() async {
    final response = await _send('GET', _uri('/api/account/export'));
    if (response.statusCode != 200) {
      throw ApiException('export account', response);
    }
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="([^"/\\]+)"').firstMatch(disposition);
    return (
      fileName: match?.group(1) ?? '217-data.json',
      bytes: response.bodyBytes,
    );
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
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final response = await _send(
      'POST',
      _uriFor(base, '/api/share/revoke'),
      body: {},
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    if (response.statusCode != 200) {
      throw ApiException('revoke share', response);
    }
    return _shareChanged(
      ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      expectedScope: scope,
      expectedBase: base,
    );
  }

  Future<ShareState> acceptShare(String code) async {
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    final response = await _send(
      'POST',
      _uriFor(base, '/api/share/accept'),
      body: {'code': code},
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
    if (response.statusCode != 200) {
      throw ApiException('accept share', response);
    }
    // Accepting makes this account a partner of that owner.
    return _shareChanged(
      ShareState.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
      expectedScope: scope,
      expectedBase: base,
      newRole: 'partner',
    );
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

  /// Asks what changed since [etag] (`GET /api/sync/status`). A 304 costs the
  /// server no database work, so this is what the periodic checks send
  /// instead of reading the inbox or the calendar. An older server without
  /// the endpoint answers [SyncStatusKind.unsupported]; offline, 401 after a
  /// failed renewal and 403 throw like any other call.
  Future<SyncStatusResult> syncStatus({String? etag}) async {
    final response = await _send(
      'GET',
      _uri('/api/sync/status'),
      headers: {
        if (etag != null && etag.isNotEmpty) 'If-None-Match': '"$etag"',
      },
    );
    switch (response.statusCode) {
      case 304:
        return const SyncStatusResult(SyncStatusKind.notModified);
      case 404:
        return const SyncStatusResult(SyncStatusKind.unsupported);
      case 200:
        return SyncStatusResult(
          SyncStatusKind.changed,
          SyncStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
        );
    }
    throw ApiException('sync status', response);
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
  Future<SessionSnapshot> setRole(String role) => _sendSession(
        'PUT',
        '/api/account/role',
        body: {'role': role},
        errorContext: 'set role',
      );

  Future<SessionSnapshot> setStage(String stage) => _sendSession(
        'PUT',
        '/api/account/stage',
        body: {'stage': stage},
        errorContext: 'set stage',
      );

  /// Sets the display name and/or birth month (`YYYY-MM`); a null field is
  /// left as is, an empty one cleared.
  Future<SessionSnapshot> updateProfile(
          {String? displayName, String? birthDate}) =>
      _sendSession(
        'PUT',
        '/api/account/profile',
        body: {
          if (displayName != null) 'display_name': displayName,
          if (birthDate != null) 'birth_date': birthDate,
        },
        errorContext: 'update profile',
      );

  /// Period history and predictions for the visible calendar. [today] is the
  /// device's local date (YYYY-MM-DD).
  /// Offline, the last predictions seen on this device.
  Future<CycleInfo> getCycle(String today) => _orCached(
        () async {
          final scope = _scope;
          final response =
              await _send('GET', _uri('/api/cycle', {'today': today}));
          if (response.statusCode != 200) {
            await _clearCalendarIfAccessDenied(scope, response);
            throw ApiException('cycle', response);
          }
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          await _verifyCalendarSubject(scope, decoded['subject_id'] as String?);
          await _keepDoc(scope, 'cycle', response.body);
          return CycleInfo.fromJson(decoded);
        },
        (userId) async {
          if (_calendarReadBlocked) return null;
          final body = await _local.readDoc(userId, 'cycle');
          return body == null
              ? null
              : CycleInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
        },
      );

  /// Which account and calendar a request was sent for; taken before the
  /// request so a late answer is never kept for another one.
  ({String? userId, int calendar, String? subjectId}) get _scope => (
        userId: _userId,
        calendar: _calendarGeneration,
        subjectId: _calendarSubjectId,
      );

  bool _isCurrent(({String? userId, int calendar, String? subjectId}) scope) =>
      scope.userId != null &&
      scope.userId == _userId &&
      scope.calendar == _calendarGeneration;

  /// Rejects calendar responses whose server-supplied `subject_id` does not
  /// match the session's active calendar owner (e.g. a partner relinked on
  /// another device while `/api/auth/session` was slow), wiping stale cached
  /// data so two owners' rows can never be mixed or saved under the wrong
  /// marker. Older servers that omit `subject_id` keep working unchanged.
  Future<void> _verifyCalendarSubject(
    ({String? userId, int calendar, String? subjectId}) scope,
    String? responseSubjectId,
  ) async {
    if (scope.userId == null ||
        responseSubjectId == null ||
        responseSubjectId.isEmpty) {
      return;
    }
    if (responseSubjectId == scope.subjectId) return;
    var fired = false;
    await _serializeAuth(() async {
      if (!_isCurrent(scope)) return;
      _calendarGeneration++;
      _sessionRevision++;
      fired = true;
      await _clearCalendarOrPersistInvalidationLocked(scope.userId!);
    });
    if (fired) onCalendarScopeMismatch?.call();
    throw const CalendarScopeMismatchException();
  }

  /// Clears cached calendar months and predictions when the server denies
  /// calendar access (revoked share, withdrawn owner consent, missing role, or
  /// rejected session) so revoked data cannot survive an offline restart.
  Future<void> _clearCalendarIfAccessDenied(
    ({String? userId, int calendar, String? subjectId}) scope,
    http.Response response,
  ) async {
    final msg = response.statusCode == 403
        ? ApiException._errorField(response.body)
        : null;
    final denied = response.statusCode == 401 ||
        (response.statusCode == 403 &&
            (msg == 'share inactive' ||
                msg == 'calendar owner consent required' ||
                msg == 'role not chosen'));
    if (!denied) return;
    final refreshSession = response.statusCode == 401 ||
        (response.statusCode == 403 &&
            (msg == 'share inactive' || msg == 'role not chosen'));
    var fired = false;
    await _serializeAuth(() async {
      if (!_isCurrent(scope)) return;
      _calendarGeneration++;
      _sessionRevision++;
      fired = true;
      await _clearCalendarOrPersistInvalidationLocked(scope.userId!);
    });
    if (fired) {
      onCalendarAccessDenied?.call(refreshSession: refreshSession);
    }
  }

  /// Saves a server answer, if it is still for the account and calendar on
  /// the device. Serialized with auth/calendar invalidation so a relink or
  /// logout cannot clear the cache between the check and the write.
  Future<void> _keepDoc(
    ({String? userId, int calendar, String? subjectId}) scope,
    String key,
    String body,
  ) =>
      _serializeAuth(() async {
        if (_isCurrent(scope)) await _local.writeDoc(scope.userId!, key, body);
      });

  Future<PartnerAlertPreference> getPartnerAlerts() => _orCached(
        () async {
          final scope = _scope;
          final response = await _send('GET', _uri('/api/partner-alerts'));
          if (response.statusCode != 200) {
            throw ApiException('partner alerts', response);
          }
          await _keepDoc(scope, 'partner_alerts', response.body);
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
    final scope = _scope;
    final response = await _send(
      'PUT',
      _uri('/api/partner-alerts'),
      body: pref.toJson(),
    );
    if (response.statusCode != 200) {
      throw ApiException('save partner alerts', response);
    }
    await _keepDoc(scope, 'partner_alerts', response.body);
    return PartnerAlertPreference.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// The month as the server has it, under the day edits still waiting;
  /// offline, as last seen on this device.
  Future<List<Entry>> listEntries(int year, int month) => _orCached(
        () async {
          final scope = _scope;
          final userId = scope.userId;
          final writes = _queueChanges;
          final response = await _send(
            'GET',
            _uri('/api/entries', {
              'year': '$year',
              'month': '$month',
            }),
          );
          if (response.statusCode != 200) {
            await _clearCalendarIfAccessDenied(scope, response);
            throw ApiException('list entries', response);
          }
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          await _verifyCalendarSubject(scope, decoded['subject_id'] as String?);
          final entries = (decoded['entries'] as List<dynamic>? ?? const [])
              .map((e) => Entry.fromJson(e as Map<String, dynamic>))
              .toList();
          if (userId == null) return entries;
          return _serializeAuth(() async {
            if (!_isCurrent(scope)) return entries;
            if (writes != _queueChanges && !_calendarReadBlocked) {
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
          });
        },
        (userId) async {
          if (_calendarReadBlocked) return null;
          return _local.monthEntries(userId, year, month);
        },
      );

  /// The device's copy of a month, without asking the server; null when it
  /// was never read here. Lets a month swiped into view draw at once.
  Future<List<Entry>?> cachedMonth(int year, int month) async {
    final userId = _userId;
    if (userId == null || _calendarReadBlocked) return null;
    return _local.monthEntries(userId, year, month);
  }

  /// The device's copy of the last cycle predictions, without asking the
  /// server; null when none was ever saved. Lets the calendar draw them at
  /// once, before the fresh answer arrives.
  Future<CycleInfo?> cachedCycle() async {
    final userId = _userId;
    if (userId == null || _calendarReadBlocked) return null;
    final body = await _local.readDoc(userId, 'cycle');
    return body == null
        ? null
        : CycleInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

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
      if (_consentBlocked) return;
      final userId = _userId;
      if (userId == null) return;
      for (final write in await _local.pendingWrites(userId)) {
        // Signed out, switched account, or consent required meanwhile.
        if (_userId != userId || _consentBlocked) return;
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
          if (retryLater) {
            // Retry a stale consent denial if acceptance requested another sync.
            if (err.statusCode == 403 &&
                err.message == 'consent required' &&
                _syncAgain &&
                !offline.value &&
                !_consentBlocked) {
              break;
            }
            return;
          }
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
    } while (_syncAgain && !_consentBlocked);
  }

  Future<ReminderPreference?> getReminderPreference() => _orCached(
        () async {
          final scope = _scope;
          final response =
              await _send('GET', _uri('/api/reminders/preferences'));
          if (response.statusCode == 404) {
            await _keepDoc(scope, 'reminder', 'null');
            return null;
          }
          if (response.statusCode != 200) {
            throw ApiException('reminder preference', response);
          }
          await _keepDoc(scope, 'reminder', response.body);
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
    final scope = _scope;
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
    await _keepDoc(scope, 'reminder', response.body);
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

  /// Signs in with email and password (first-party sign-in). On 403 `verify
  /// your email to sign in` the caller shows the verification screen; a 429
  /// carries its Retry-After seconds in [ApiException.retryAfter].
  Future<User> signInWithPassword(String email, String password) async {
    invalidatePendingAuth();
    final scope = _scopeEpoch;
    final base = config.apiBaseUrl;
    int? keyGen;
    final devicePublicKey = await _serializeAuth(() async {
      if (_scopeChanged(scope, base)) throw const StaleAuthScopeException();
      keyGen = ++_deviceKeyGen;
      return _deviceKey.create();
    });
    Future<void> deleteOwnedDeviceKey() => _serializeAuth(() async {
          if (devicePublicKey != null && keyGen == _deviceKeyGen) {
            await _deviceKey.delete();
          }
        });
    final response = await _send(
      'POST',
      _uriFor(base, '/api/auth/password/login'),
      body: {
        'email': email,
        'password': password,
        if (devicePublicKey != null) 'device_public_key': devicePublicKey,
      },
      auth: false,
      expectedScope: scope,
      expectedBase: base,
    );
    if (_scopeChanged(scope, base)) {
      await deleteOwnedDeviceKey();
      throw const StaleAuthScopeException();
    }
    if (response.statusCode != 200) {
      await deleteOwnedDeviceKey();
      throw ApiException('password sign-in', response);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final userJson = decoded['user'] as Map<String, dynamic>?;
    final token = decoded['session_token'] as String?;
    // Browsers get only the HttpOnly cookie; other clients need the token.
    if (userJson == null || (token == null && !kIsWeb)) {
      await deleteOwnedDeviceKey();
      throw ApiException('password sign-in', response);
    }
    final snapshot = SessionSnapshot.fromJson(decoded);
    var shouldSync = false;
    await _serializeAuth(() async {
      if (_scopeChanged(scope, base)) {
        if (devicePublicKey != null && keyGen == _deviceKeyGen) {
          await _deviceKey.delete();
        }
        throw const StaleAuthScopeException();
      }
      invalidatePendingAuth();
      await _dropLocalDataLocked();
      if (token != null) await saveSessionToken(token);
      final keyId = decoded['device_key_id'];
      if (keyId is String && keyId.isNotEmpty) {
        await _storage.write(key: _deviceKeyIdKey, value: keyId);
      } else {
        await _storage.delete(key: _deviceKeyIdKey);
        if (devicePublicKey != null && keyGen == _deviceKeyGen) {
          await _deviceKey.delete();
        }
      }
      shouldSync = await _applySessionLocked(decoded, snapshot);
      invalidatePendingAuth();
    });
    if (shouldSync) unawaited(syncPending());
    return User.fromJson(userJson);
  }

  /// Asks the verification code again for [email] (mail configured).
  Future<void> resendVerification(String email) async {
    final response = await _sendOnce(
      'POST',
      _uri('/api/auth/password/verify/resend'),
      body: {'email': email},
      auth: false,
    );
    if (response.statusCode != 200) {
      throw ApiException('resend verification', response);
    }
  }

  /// Confirms the address with the code from the verification mail.
  Future<void> verifyEmail(String email, String code) async {
    final response = await _sendOnce(
      'POST',
      _uri('/api/auth/password/verify'),
      body: {'email': email, 'code': code},
      auth: false,
    );
    if (response.statusCode != 200) {
      throw ApiException('verify email', response);
    }
  }

  /// Creates an account with email and password (no session yet; with mail
  /// configured the address must be verified before the first sign-in).
  Future<void> signUpWithPassword(String email, String password) async {
    final response = await _sendOnce(
      'POST',
      _uri('/api/auth/password/signup'),
      body: {'email': email, 'password': password},
      auth: false,
    );
    if (response.statusCode != 201) {
      throw ApiException('sign up', response);
    }
  }

  /// Sets or changes the signed-in account's password. 403 `current password
  /// is wrong` comes back as a 403 [ApiException].
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _send(
      'PUT',
      _uri('/api/account/password'),
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    if (response.statusCode != 204) {
      throw ApiException('change password', response);
    }
  }

  Future<String> beginOIDCLink(String platform) async {
    final response = await _send('POST', _uri('/api/account/oidc/link'),
        body: {'platform': platform});
    if (response.statusCode != 200) throw ApiException('connect', response);
    final url = (jsonDecode(response.body) as Map)['url'];
    if (url is! String || url.isEmpty) throw StateError('missing link URL');
    return url;
  }

  Future<void> confirmOIDCLink(String code) async {
    final response = await _send('POST', _uri('/api/account/oidc/link/confirm'),
        body: {'code': code});
    if (response.statusCode != 204) throw ApiException('connect', response);
  }

  Future<void> removeOIDC() async {
    final response = await _send('DELETE', _uri('/api/account/oidc'));
    if (response.statusCode != 204) throw ApiException('disconnect', response);
  }

  /// Removes the account's password credential (another sign-in method must
  /// remain; the server answers 409 otherwise).
  Future<void> removePassword() async {
    final response = await _send('DELETE', _uri('/api/account/password'));
    if (response.statusCode != 204) {
      throw ApiException('remove password', response);
    }
  }
}

class OIDCSignInException implements Exception {
  const OIDCSignInException(this.reason);
  final String reason;
}

/// Result of [ApiClient.checkServer].
enum ServerCheck { ok, unreachable, notA217Server, signInNotConfigured }

/// Thrown when an auth/session operation completes after the active server or
/// account scope changed (sign-in, logout, or server switch).
class StaleAuthScopeException implements Exception {
  const StaleAuthScopeException();

  @override
  String toString() => 'stale auth scope';
}

/// Thrown when a calendar response reports a different owner `subject_id` than
/// the session's active calendar scope (for example after a partner relinks on
/// another device while `/api/auth/session` is still pending).
class CalendarScopeMismatchException implements Exception {
  const CalendarScopeMismatchException();

  @override
  String toString() => 'calendar scope mismatch';
}

/// Non-success API response. [message] is the server's `error` field, if any.
class ApiException implements Exception {
  ApiException(this.action, http.Response response)
      : statusCode = response.statusCode,
        message = _errorField(response.body),
        consentVersion = _consentVersionField(response.body),
        retryAfter = _retryAfter(response.headers['retry-after']);

  final String action;
  final int statusCode;
  final String message;
  final int? consentVersion;

  /// Seconds to wait before trying again (429 rate limits).
  final int? retryAfter;

  static int? _retryAfter(String? value) {
    if (value == null) return null;
    return int.tryParse(value.trim());
  }

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
