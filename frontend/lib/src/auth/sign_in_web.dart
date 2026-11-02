// Web-only implementation (selected via conditional import in sign_in.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../api/client.dart';
import '../models.dart';

/// Browser cookie flow:
/// 1) Same-origin GET /api/auth/workos (JSON) sets 217_oauth_binding.
/// 2) Navigate to AuthKit from the Entrar click — no HTML "continue" interstitial.
/// WorkOS returns to /api/auth/workos/callback which sets the session cookie,
/// then lands on the app, or on [returnTo] (one of the privacy pages, e.g.
/// `/app/privacy?confirm=delete`; the server ignores any other path).
Future<User?> beginWorkOSSignIn(ApiClient api, {String? returnTo}) async {
  final base = api.config.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  var target = base.isEmpty ? '/api/auth/workos' : '$base/api/auth/workos';
  if (returnTo != null && returnTo.isNotEmpty) {
    target += '?${Uri(queryParameters: {'return': returnTo}).query}';
  }
  final req = await html.HttpRequest.request(
    target,
    method: 'GET',
    requestHeaders: const {
      'Accept': 'application/json',
    },
    withCredentials: true,
  );
  if (req.status != 200) {
    throw StateError('auth start failed: HTTP ${req.status}');
  }
  final body = req.responseText ?? '';
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw StateError('auth start returned unexpected body');
  }
  final authURL = decoded['auth_url'] as String? ?? '';
  if (authURL.isEmpty) {
    throw StateError('auth start missing auth_url');
  }
  html.window.location.assign(authURL);
  return Completer<User?>().future;
}
