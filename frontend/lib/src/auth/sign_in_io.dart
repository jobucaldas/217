import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../api/client.dart';
import '../models.dart';

Future<User?> beginWorkOSSignIn(ApiClient api, {String? returnTo}) =>
    api.signInWithWorkOS();

Future<User?> beginOIDCSignIn(ApiClient api, {String? returnTo}) =>
    api.signInWithOIDC();

Future<bool> connectOIDC(ApiClient api) async {
  final url = await api.beginOIDCLink('android');
  final result = await FlutterWebAuth2.authenticate(
    url: url,
    callbackUrlScheme: 'com.caldasstudios.app217',
    options: const FlutterWebAuth2Options(useWebview: false),
  );
  return Uri.parse(result).queryParameters['linked'] == '1';
}
