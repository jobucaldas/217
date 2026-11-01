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

/// Tags are `0.<yy>.<MMDD>-<run>` (UTC date, then the build of that day, from 1).
/// The rolling `nightly` release does not match.
final _tagPattern = RegExp(r'^0\.(\d{2})\.(\d{4})-(\d+)$');

/// Builds before this scheme were tagged `<yyyyMMddHHmmss>_<short sha>`; they
/// are older than every tag in the current scheme.
final _legacyTagPattern = RegExp(r'^\d{14}_[0-9a-f]{7}$');

/// Orderable key of a current-scheme tag, or null when [tag] is not one.
List<int>? _versionKey(String tag) {
  final m = _tagPattern.firstMatch(tag);
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// The newest published release whose APK is newer than [installed], or null
/// when there is none. Never throws: any failure reads as "no update".
Future<AvailableUpdate?> checkForUpdate({
  required http.Client client,
  String installed = appVersion,
}) async {
  try {
    // A legacy-tagged build is older than any current tag ([0, 0, 0] sorts first).
    final installedKey = _versionKey(installed) ??
        (_legacyTagPattern.hasMatch(installed) ? const [0, 0, 0] : null);
    if (installedKey == null) return null;
    final response = await client.get(
      _releasesUrl,
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final releases = jsonDecode(response.body);
    if (releases is! List) return null;

    Map<String, dynamic>? newest;
    List<int>? newestKey;
    String? newestTag;
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      final tag = release['tag_name'];
      if (release['draft'] == true || tag is! String) continue;
      final key = _versionKey(tag);
      if (key == null) continue;
      if (newestKey == null || _compare(key, newestKey) > 0) {
        newest = release;
        newestKey = key;
        newestTag = tag;
      }
    }
    if (newest == null || newestKey == null || newestTag == null) return null;
    if (_compare(newestKey, installedKey) <= 0) return null;

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
