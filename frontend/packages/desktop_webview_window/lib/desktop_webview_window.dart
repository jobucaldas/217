/// The slice of desktop_webview_window's API that flutter_web_auth_2 compiles
/// against. No embedded webview exists: [WebviewWindow.isWebviewAvailable] is
/// false, so flutter_web_auth_2 only ever takes its system-browser path.
library;

class CreateConfiguration {
  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.title = '',
    this.titleBarTopPadding = 0,
    this.userDataFolderWindows = '',
  });

  final int windowWidth;
  final int windowHeight;
  final String title;
  final int titleBarTopPadding;
  final String userDataFolderWindows;
}

typedef OnUrlRequestCallback = void Function(String url);

abstract class Webview {
  Future<void> get onClose;
  void addOnUrlRequestCallback(OnUrlRequestCallback callback);
  void launch(String url);
  void close();
}

class WebviewWindow {
  static Future<bool> isWebviewAvailable() async => false;

  static Future<Webview> create({CreateConfiguration? configuration}) =>
      Future.error(UnsupportedError('Embedded webviews are not bundled'));
}
