import 'dart:io' show Platform;
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

/// One-off check just before the partner's pill-not-logged alert.
const _precheckUniqueName = 'partner-precheck';
const _precheckTaskName = 'com.caldasstudios.app217.partnerPrecheck';

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
    final isPrecheck = task == _precheckTaskName;
    DateTime? deferredPrecheck;
    try {
      await checkMessagesInBackground(
        config: AppConfig.fromEnvironment(),
        client: client,
        prefs: AppearancePrefs(),
        deviceLanguage: AppLanguageX.fromDevice(
          PlatformDispatcher.instance.locales.map((l) => l.languageCode),
        ),
        schedulePrecheck: isPrecheck
            ? (at) async {
                deferredPrecheck = at;
              }
            : schedulePartnerPrecheck,
      );
      if (isPrecheck && deferredPrecheck != null) {
        await schedulePartnerPrecheck(deferredPrecheck);
      }
    } catch (_) {
      // Offline or server error: the next periodic run tries again.
    } finally {
      client.close();
    }
    return true;
  });
}

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  await Workmanager().initialize(messageWorkerDispatcher);
  _initialized = true;
}

Future<void> syncMessageWorker({required bool enabled}) async {
  // Check the host OS, not defaultTargetPlatform: widget tests on Linux run
  // with TargetPlatform.android and would otherwise dispatch to
  // WorkmanagerLinux (spawning a subprocess inside FakeAsync).
  if (!Platform.isAndroid) return;
  try {
    await _ensureInitialized();
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
      await Workmanager().cancelByUniqueName(_precheckUniqueName);
    }
  } catch (_) {
    // Missing plugin (tests, desktop) or WorkManager refused: foreground
    // checks still run.
  }
}

Future<void> schedulePartnerPrecheck(DateTime? at) async {
  if (!Platform.isAndroid) return;
  try {
    await _ensureInitialized();
    if (at == null) {
      await Workmanager().cancelByUniqueName(_precheckUniqueName);
      return;
    }
    final delay = at.difference(DateTime.now());
    await Workmanager().registerOneOffTask(
      _precheckUniqueName,
      _precheckTaskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
      constraints: Constraints(networkType: NetworkType.connected),
      // One check at a time: the newest plan wins.
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (_) {
    // Missing plugin or WorkManager refused: the periodic check still runs.
  }
}
