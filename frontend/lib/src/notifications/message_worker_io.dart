import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../api/platform_http.dart';
import '../config.dart';
import '../i18n.dart';
import '../prefs.dart';
import 'message_background_check.dart';

const _uniqueName = 'message-check';
const _taskName = 'com.caldasstudios.app217.messageCheck';

/// Android WorkManager's floor for periodic work.
const _every = Duration(minutes: 15);

bool _initialized = false;

/// Background isolate entry point: WorkManager starts a headless engine and
/// runs this, with the app in the background or not running at all.
@pragma('vm:entry-point')
void messageWorkerDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, _) async {
    final client = createPlatformHttpClient();
    try {
      await checkMessagesInBackground(
        config: AppConfig.fromEnvironment(),
        client: client,
        prefs: AppearancePrefs(),
        deviceLanguage: AppLanguageX.fromDevice(
          PlatformDispatcher.instance.locales.map((l) => l.languageCode),
        ),
      );
    } catch (_) {
      // Offline or server error: the next periodic run tries again.
    } finally {
      client.close();
    }
    return true;
  });
}

Future<void> syncMessageWorker({required bool enabled}) async {
  if (!isAndroidPlatform) return;
  try {
    if (!_initialized) {
      await Workmanager().initialize(messageWorkerDispatcher);
      _initialized = true;
    }
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: _every,
        constraints: Constraints(networkType: NetworkType.connected),
        // Keeps the running schedule; only changed settings are applied.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(_uniqueName);
    }
  } catch (_) {
    // Missing plugin (tests, desktop) or WorkManager refused: foreground
    // checks still run.
  }
}
