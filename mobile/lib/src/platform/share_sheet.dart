import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.jobucaldas.a217/share');

/// True when this build can open the OS share sheet (Android).
bool get canShareNatively =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Opens the Android share sheet (WhatsApp, SMS, email…) with [text].
/// Returns false when no sheet could be shown, so callers can fall back to
/// copying the text instead.
Future<bool> shareText(String text, {String? subject}) async {
  if (!canShareNatively) return false;
  try {
    await _channel.invokeMethod<void>('shareText', {
      'text': text,
      if (subject != null) 'subject': subject,
    });
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
