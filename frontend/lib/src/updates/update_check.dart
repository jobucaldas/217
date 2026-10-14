import 'dart:convert';

import 'package:http/http.dart' as http;

/// Release tag this build came from (`--dart-define=APP_VERSION=<tag>`).
/// Empty for dev builds, which never offer updates.
const appVersion = String.fromEnvironment('APP_VERSION');

/// A published release newer than the installed build, with its APK.
class AvailableUpdate {
  const AvailableUpdate({required this.tag, required this.apkUrl});

  final String tag;
  final Uri apkUrl;
}

final _releasesUrl = Uri.parse(
  'https://api.github.com/repos/jobucaldas/217/releases?per_page=10',
);

/// The APK is only ever offered from the project's own release downloads.
const _downloadPrefix = 'https://github.com/jobucaldas/217/releases/download/';

/// Tags are `<UTC yyyyMMddHHmmss>_<short sha>`, so they sort by time as plain
/// strings. The rolling `nightly` release does not match.
final _tagPattern = RegExp(r'^\d{14}_[0-9a-f]{7}$');

/// The newest published release whose APK is newer than [installed], or null
/// when there is none. Never throws: any failure reads as "no update".
Future<AvailableUpdate?> checkForUpdate({
  required http.Client client,
  String installed = appVersion,
}) async {
  try {
    if (!_tagPattern.hasMatch(installed)) return null;
    final response = await client.get(
      _releasesUrl,
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final releases = jsonDecode(response.body);
    if (releases is! List) return null;

    Map<String, dynamic>? newest;
    String? newestTag;
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      final tag = release['tag_name'];
      if (release['draft'] == true ||
          tag is! String ||
          !_tagPattern.hasMatch(tag)) {
        continue;
      }
      if (newestTag == null || tag.compareTo(newestTag) > 0) {
        newest = release;
        newestTag = tag;
      }
    }
    if (newest == null || newestTag == null) return null;
    if (newestTag.compareTo(installed) <= 0) return null;

    final assets = newest['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || !name.endsWith('.apk') || url is! String) {
        continue;
      }
      final apkUrl = Uri.tryParse(url);
      if (apkUrl == null || !url.startsWith(_downloadPrefix)) return null;
      return AvailableUpdate(tag: newestTag, apkUrl: apkUrl);
    }
    return null;
  } catch (_) {
    return null;
  }
}
