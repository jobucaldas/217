// Web-only implementation (selected via conditional import in save_data.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'save_data_outcome.dart';

export 'save_data_outcome.dart';

/// Downloads [content] as a file named [name] (no server round trip).
Future<SaveDataOutcome> saveDataFile(String name, String content) async {
  final blob = html.Blob([content], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final link = html.AnchorElement(href: url)
    ..download = name
    ..style.display = 'none';
  html.document.body?.append(link);
  link.click();
  link.remove();
  html.Url.revokeObjectUrl(url);
  return const SaveDataOutcome(SaveDataHow.downloaded);
}
