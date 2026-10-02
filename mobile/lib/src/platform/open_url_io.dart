import 'package:flutter/services.dart';

import 'share_sheet.dart';

Future<bool> openExternalUrl(String url) async {
  try {
    await intentsChannel.invokeMethod<void>('openUrl', {'url': url});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
