import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android intents bridge (share sheet) in `MainActivity.kt`.
const intentsChannel = MethodChannel('com.jobucaldas.a217/intents');

/// True when this build can open the OS share sheet (Android).
bool get canShareNatively =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Opens the Android share sheet (WhatsApp, SMS, email…) with [text].
/// Returns false when no sheet could be shown, so callers can fall back to
/// copying the text instead.
Future<bool> shareText(String text, {String? subject}) async {
  if (!canShareNatively) return false;
  try {
    await intentsChannel.invokeMethod<void>('shareText', {
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
