// Web-only implementation (selected via conditional import in open_url.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<bool> openExternalUrl(String url) async {
  html.window.open(url, '_blank', 'noopener');
  return true;
}
