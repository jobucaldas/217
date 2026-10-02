import 'open_url_io.dart' if (dart.library.html) 'open_url_web.dart' as impl;

/// Self-hosting guide (README section). Override per build with
/// `--dart-define=SELF_HOST_GUIDE_URL=...`.
const selfHostGuideUrl = String.fromEnvironment(
  'SELF_HOST_GUIDE_URL',
  defaultValue: 'https://github.com/jobucaldas/217#self-hosting',
);

/// Opens [url] in the browser (new tab on web). Returns false when nothing
/// could open it.
Future<bool> openExternalUrl(String url) => impl.openExternalUrl(url);
