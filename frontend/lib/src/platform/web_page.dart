import 'web_page_io.dart' if (dart.library.html) 'web_page_web.dart' as impl;

/// Web only: loads [path] (same origin) in this tab. Elsewhere does nothing.
void goToWebPath(String path) => impl.goToWebPath(path);

/// Web only: shows [path] in the address bar without loading it.
void replaceWebPath(String path) => impl.replaceWebPath(path);

/// Web only: saves [bytes] as a download named [fileName]. Returns false
/// where there is no browser to save it.
bool saveDownload(String fileName, List<int> bytes, String mimeType) =>
    impl.saveDownload(fileName, bytes, mimeType);
