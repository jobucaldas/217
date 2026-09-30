// Web-only implementation (selected via conditional import in sign_in.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import '../api/client.dart';
import '../models.dart';

/// Browser cookie flow: full-page navigate to the Go AuthKit start endpoint.
/// WorkOS redirects back to /api/auth/workos/callback which sets the session
/// cookie and returns the user to the Flutter web app.
Future<User?> beginWorkOSSignIn(ApiClient api) {
  final base = api.config.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  final target = base.isEmpty ? '/api/auth/workos' : '$base/api/auth/workos';
  html.window.location.assign(target);
  return Completer<User?>().future;
}
