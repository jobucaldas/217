import '../api/client.dart';
import '../models.dart';

Future<User?> beginWorkOSSignIn(ApiClient api, {String? returnTo}) {
  throw UnsupportedError('WorkOS sign-in is unavailable on this platform');
}
