import '../api/client.dart';
import '../models.dart';

Future<User?> beginWorkOSSignIn(ApiClient api, {String? returnTo}) {
  throw UnsupportedError('WorkOS sign-in is unavailable on this platform');
}

Future<User?> beginOIDCSignIn(ApiClient api, {String? returnTo}) =>
    throw UnsupportedError('OIDC sign-in is unavailable on this platform');

Future<bool> connectOIDC(ApiClient api) =>
    throw UnsupportedError('OIDC linking is unavailable on this platform');
