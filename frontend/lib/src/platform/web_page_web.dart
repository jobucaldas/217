// Web-only implementation (selected via conditional import in web_page.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

void goToWebPath(String path) => html.window.location.assign(path);

void replaceWebPath(String path) =>
    html.window.history.replaceState(null, '', path);

bool saveDownload(String fileName, List<int> bytes, String mimeType) {
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoked later: some browsers start the download after click() returns.
  Future<void>.delayed(const Duration(minutes: 1), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}
