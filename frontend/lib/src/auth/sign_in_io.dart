import '../api/client.dart';
import '../models.dart';

Future<User?> beginWorkOSSignIn(ApiClient api, {String? returnTo}) =>
    api.signInWithWorkOS();
