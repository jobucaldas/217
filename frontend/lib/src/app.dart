import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/client.dart';
import 'auth/sign_in.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'notifications/local_reminders.dart';
import 'notifications/daily_reminder_sync_queue.dart';
import 'notifications/partner_alert_sync_queue.dart';
import 'platform/open_url.dart';
import 'prefs.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/privacy_screens.dart';
import 'screens/role_screen.dart';
import 'screens/server_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_screens.dart';
import 'theme/app_theme.dart';
import 'screens/dialog_actions.dart';

class App217 extends StatefulWidget {
  const App217({
    super.key,
    required this.config,
    this.api,
    this.dailyReminderScheduler,
    this.partnerAlertCanceller,
    this.partnerAlertScheduler,
  });

  final AppConfig config;

  /// Injected client for tests; production builds one from [config].
  final ApiClient? api;
  final DailyReminderScheduler? dailyReminderScheduler;
  final Future<void> Function()? partnerAlertCanceller;
  final PartnerAlertScheduler? partnerAlertScheduler;

  @override
  State<App217> createState() => _App217State();
}

class _App217State extends State<App217> {
  late final ApiClient _api = (widget.api ?? ApiClient(widget.config))
    ..onConsentRequired = _onOwnConsentRequired;
  late final AppearancePrefs _prefs = AppearancePrefs();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  User? _user;
  ShareState _share = const ShareState(status: 'none');
  bool _loading = true;

  /// Signed in but not yet agreed to the server's privacy notice.
  bool _consentRequired = false;
  int _consentVersion = 0;
  AppLanguage _language = _deviceLanguage();
  ThemeMode _themeMode = ThemeMode.system;
  AppPalette _palette = AppPalette.blue;
  bool _reminderHintDismissed = false;

  /// Whether the daily reminder is on; null until known (no bubble then).
  bool? _remindersOn;
  int _sessionGeneration = 0;

  /// Routes pushed on top of home (Settings) are built once, so they listen
  /// here to pick up theme, language and session changes made from them.
  final _changes = _ChangeTicker();
  final ValueNotifier<int> _stageChanges = ValueNotifier(0);
  late final DailyReminderSyncQueue _dailyReminderSyncQueue =
      DailyReminderSyncQueue(
    widget.dailyReminderScheduler ?? syncLocalDailyReminder,
  );
  late final PartnerAlertSyncQueue _partnerAlertSyncQueue =
      PartnerAlertSyncQueue(
    scheduler: widget.partnerAlertScheduler ?? syncPartnerAlerts,
    canceller: widget.partnerAlertCanceller,
  );

  Strings get _strings => Strings(_language);

  /// No saved choice: follow the device's preferred languages, else English.
  static AppLanguage _deviceLanguage() => AppLanguageX.fromDevice(
        WidgetsBinding.instance.platformDispatcher.locales
            .map((locale) => locale.languageCode),
      );

  @override
  void initState() {
    super.initState();
    _api.onConsentRequired = _onOwnConsentRequired;
    _bootstrap();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.notify();
  }

  @override
  void dispose() {
    _changes.dispose();
    _stageChanges.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Local prefs first, so theme and language hold even when offline.
    try {
      // Web invite link (`/?invite=CODE`): keep the code across sign-in.
      final linkInvite = Uri.base.queryParameters['invite']?.trim() ?? '';
      if (linkInvite.isNotEmpty) await _prefs.savePendingInvite(linkInvite);
      final appearance = await _prefs.load();
      final language = await _prefs.loadLanguage();
      final hintGone = await _prefs.reminderHintDismissed();
      if (!mounted) return;
      setState(() {
        _themeMode = appearance.mode;
        _palette = appearance.palette;
        _language = language ?? _deviceLanguage();
        _reminderHintDismissed = hintGone;
      });
    } catch (_) {
      // Keep defaults.
    }

    User? user;
    var share = const ShareState(status: 'none');
    SessionSnapshot? session;
    try {
      await _api.loadPersistedApiBase();
      if (!_api.config.needsServerSetup) {
        await _api.loadAuthConfig();
        session = await _api.currentSession();
        _clearRemindersIfConsentRequired(session);
        if (session.user == null) unawaited(_cancelAllNotifications());
        user = session.user;
        share = session.share ?? share;
      }
    } catch (_) {
      // Unreachable server: show the signed-out screen.
    }
    if (!mounted) return;
    _sessionGeneration++;
    setState(() {
      _user = user;
      _share = share;
      _setConsent(session);
      _loading = false;
    });
    if (user != null && !_consentRequired) {
      unawaited(_loadRemindersState());
      await _offerPendingInvite();
    }
  }

  Future<void> _loadRemindersState() async {
    try {
      final pref = await _api.getReminderPreference();
      if (mounted) setState(() => _remindersOn = pref?.enabled ?? false);
    } catch (_) {
      // Unknown state: stay quiet rather than nag.
    }
  }

  /// Toggling reminders re-arms the calendar bubble for the next time they
  /// are off.
  Future<void> _onRemindersToggled(bool enabled) async {
    await _prefs.resetReminderHint();
    if (!mounted) return;
    setState(() {
      _remindersOn = enabled;
      _reminderHintDismissed = false;
    });
  }

  Future<void>? _consentRecovery;

  /// One session refresh at a time, however many requests were refused.
  Future<void> _recoverConsent() => _consentRecovery ??= _refreshSession()
      .catchError((Object _) {})
      .whenComplete(() => _consentRecovery = null);

  void _onOwnConsentRequired() {
    unawaited(_cancelDailyReminder());
    unawaited(_cancelPartnerAlerts());
    unawaited(_recoverConsent());
  }

  Future<void> _refreshSession() async {
    await _api.loadAuthConfig();
    final session = await _api.currentSession();
    _clearRemindersIfConsentRequired(session);
    if (!mounted) return;
    _cancelOwnerReminderIfSessionLeavesOwner(session);
    _cancelPartnerAlertsIfSessionLeavesPartner(session);
    _sessionGeneration++;
    setState(() {
      _user = session.user;
      _share = session.share ?? const ShareState(status: 'none');
      _setConsent(session);
    });
    if (session.consentRequired) {
      _navKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _refreshConsentSession() async {
    final session = await _api.currentSession();
    if (!mounted) return;
    _sessionGeneration++;
    setState(() {
      _user = session.user;
      _share = session.share ?? const ShareState(status: 'none');
      _setConsent(session);
    });
  }

  void _clearRemindersIfConsentRequired(SessionSnapshot session) {
    if (session.consentRequired) {
      unawaited(_cancelDailyReminder());
      unawaited(_cancelPartnerAlerts());
      // Do not delay showing the consent screen on local notification APIs.
      // Their failed channel calls are best effort; the next launch retries.
    }
  }

  Future<void> _cancelAllNotifications() {
    unawaited(_cancelDailyReminder());
    return _cancelPartnerAlerts();
  }

  Future<void> _cancelDailyReminder() => _dailyReminderSyncQueue.cancel(
        title: '217',
        body: _strings.recordToday,
      );

  void _cancelOwnerReminderIfSessionLeavesOwner(SessionSnapshot session) {
    final nextUser = session.user;
    if (_user?.isOwner == true &&
        (nextUser == null || nextUser.id != _user!.id || !nextUser.isOwner)) {
      unawaited(_cancelDailyReminder());
    }
  }

  void _cancelPartnerAlertsIfSessionLeavesPartner(SessionSnapshot session) {
    final nextUser = session.user;
    if (_user?.isPartner == true &&
        (nextUser == null || nextUser.id != _user!.id || !nextUser.isPartner)) {
      unawaited(_cancelPartnerAlerts());
    }
  }

  Future<void> _cancelPartnerAlerts() async {
    await _partnerAlertSyncQueue.cancel();
  }

  /// Call inside setState with each session the server returns.
  void _setConsent(SessionSnapshot? session) {
    if (session?.user == null) {
      _consentRequired = false;
      return;
    }
    _consentRequired = session!.consentRequired;
    _consentVersion = session.consentVersion;
  }

  /// Agreed to the privacy notice: the app can load and offer what waited.
  Future<void> _onConsented(SessionSnapshot session) async {
    _applySession(session);
    final generation = _sessionGeneration;
    unawaited(_restoreOwnerReminderAfterConsent(session, generation));
    await _offerPendingInvite();
  }

  Future<void> _restoreOwnerReminderAfterConsent(
    SessionSnapshot session,
    int generation,
  ) async {
    final user = session.user;
    if (session.consentRequired || user == null || !user.isOwner) return;

    // Consent recovery can race the cancellation started by bootstrap. Let it
    // finish before re-arming the saved local reminder.
    await _dailyReminderSyncQueue.whenIdle;
    if (!_isCurrentConsentedOwner(user.id, generation)) return;
    final reminderRevision = _dailyReminderSyncQueue.revision;

    try {
      final pref = await _api.getReminderPreference();
      if (!_isCurrentConsentedOwner(user.id, generation) ||
          !_dailyReminderSyncQueue.isCurrent(reminderRevision)) {
        return;
      }
      if (mounted) setState(() => _remindersOn = pref?.enabled ?? false);
      if (pref?.enabled != true ||
          (!supportsLocalReminders && widget.dailyReminderScheduler == null)) {
        return;
      }

      // Permission denial leaves the saved preference on. The reminder
      // settings screen continues to report permissionDenied on its next load.
      await _dailyReminderSyncQueue.scheduleIfCurrent(
        revision: reminderRevision,
        enabled: true,
        timeHhMm: pref!.time,
        title: '217',
        body: _strings.recordToday,
      );
    } catch (_) {
      // Consent is already accepted; a reminder restore failure must not gate
      // the calendar or change the saved preference.
    }
  }

  bool _isCurrentConsentedOwner(String userId, int generation) =>
      mounted &&
      generation == _sessionGeneration &&
      !_consentRequired &&
      _user?.id == userId &&
      _user!.isOwner;

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _prefs.saveThemeMode(mode);
  }

  Future<void> _setPalette(AppPalette palette) async {
    setState(() => _palette = palette);
    await _prefs.savePalette(palette);
  }

  Future<void> _setLanguage(AppLanguage language) async {
    setState(() => _language = language);
    await _prefs.saveLanguage(language);
  }

  /// After sign-in, offers to join the calendar from an opened invite link
  /// when this account can join one: no role picked yet (joining makes it a
  /// partner), or a partner not linked to a calendar. Owners never join.
  Future<void> _offerPendingInvite() async {
    // Joining waits for consent; the code stays saved until then.
    if (_consentRequired) return;
    final code = (await _prefs.pendingInvite())?.trim() ?? '';
    final user = _user;
    if (code.isEmpty || user == null || !mounted) return;
    final canJoin = !user.hasRole || (user.isPartner && !_share.isActive);
    if (!canJoin) {
      // e.g. the owner opened their own link: nothing to offer.
      await _prefs.clearPendingInvite();
      return;
    }
    final navContext = _navKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    final strings = _strings;
    final join = await showDialog<bool>(
      context: navContext,
      builder: (context) => AlertDialog(
        title: Text(strings.pendingInviteTitle),
        content: Text(strings.pendingInviteBody(code)),
        actions: [
          DialogActionRow(
            secondary: DialogLinkButton(
              onPressed: () => Navigator.pop(context, false),
              label: strings.notNow,
            ),
            primary: FilledButton(
              key: const ValueKey('pending-invite-join'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.joinCalendar),
            ),
          ),
        ],
      ),
    );
    await _prefs.clearPendingInvite();
    if (join != true || !mounted) return;
    try {
      await _onJoinedCalendar(await _api.acceptShare(code));
    } catch (err) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(joinErrorText(_strings, err))),
      );
    }
  }

  /// This account now views someone else's calendar: its role changed, so
  /// reload the session and return to the (partner) calendar.
  Future<void> _onJoinedCalendar(ShareState share) async {
    setState(() => _share = share);
    _navKey.currentState?.popUntil((route) => route.isFirst);
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(_strings.joinedCalendar)),
    );
    await _refreshSession();
  }

  void _applySession(SessionSnapshot session) {
    _cancelOwnerReminderIfSessionLeavesOwner(session);
    _cancelPartnerAlertsIfSessionLeavesPartner(session);
    _sessionGeneration++;
    setState(() {
      _user = session.user ?? _user;
      _share = session.share ?? const ShareState(status: 'none');
      if (session.user != null) _setConsent(session);
    });
  }

  void _onStageChanged(SessionSnapshot session) {
    _applySession(session);
    _stageChanges.value++;
  }

  /// Role picked (first sign-in) or switched.
  Future<void> _onRoleChosen(SessionSnapshot session) async {
    _applySession(session);
    _navKey.currentState?.popUntil((route) => route.isFirst);
    await _offerPendingInvite();
  }

  Future<void> _switchToOwner() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) return;
    final session = await confirmRoleSwitch(
      context: navContext,
      api: _api,
      strings: _strings,
      role: 'owner',
    );
    if (session != null && mounted) _applySession(session);
  }

  /// A different server means a different account: the API client already
  /// dropped the old token, so show the signed-out state.
  void _onApiBaseChanged() {
    unawaited(_cancelAllNotifications());
    _sessionGeneration++;
    setState(() {
      _user = null;
      _share = const ShareState(status: 'none');
      _remindersOn = null;
    });
  }

  /// Server set up (first launch) or switched from the sign-in screen.
  Future<void> _onServerConnected({
    required bool changed,
    String? inviteCode,
  }) async {
    if (inviteCode != null) await _prefs.savePendingInvite(inviteCode);
    await _api.loadAuthConfig();
    if (!mounted) return;
    if (changed) {
      _onApiBaseChanged();
    } else {
      setState(() {});
    }
  }

  Future<void> _openSelfHostGuide() async {
    if (await openExternalUrl(selfHostGuideUrl)) return;
    await Clipboard.setData(const ClipboardData(text: selfHostGuideUrl));
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(_strings.linkCopied)),
    );
  }

  void _openServerSetup() {
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => ServerSetupScreen(
            api: _api,
            strings: _strings,
            changing: true,
            onConnected: ({required changed, inviteCode}) {
              Navigator.of(context).pop();
              _onServerConnected(changed: changed, inviteCode: inviteCode);
            },
            onOpenGuide: _openSelfHostGuide,
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await _api.loadAuthConfig();
      final user = await beginWorkOSSignIn(_api);
      if (!mounted) return;
      if (user != null) {
        final session = await _api.currentSession();
        _clearRemindersIfConsentRequired(session);
        if (!mounted) return;
        _sessionGeneration++;
        setState(() {
          _user = session.user ?? user;
          _share = session.share ?? const ShareState(status: 'none');
          _setConsent(session);
          _loading = false;
        });
        if (!_consentRequired) {
          unawaited(_loadRemindersState());
          await _offerPendingInvite();
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Closing the AuthKit browser tab is not an error worth announcing.
      if (err is PlatformException && err.code == 'CANCELED') return;
      if (kDebugMode) debugPrint('sign-in failed: $err');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(_strings.signInError)),
      );
    }
  }

  Future<void> _logout() async {
    _sessionGeneration++;
    unawaited(_cancelAllNotifications());
    await _api.logout();
    if (!mounted) return;
    setState(() {
      _remindersOn = null;
      _user = null;
      _share = const ShareState(status: 'none');
      _remindersOn = null;
    });
  }

  void _onAccountDeleted() {
    _sessionGeneration++;
    unawaited(_cancelAllNotifications());
    setState(() {
      _user = null;
      _share = const ShareState(status: 'none');
      _remindersOn = null;
    });
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(_strings.accountDeleted)),
    );
  }

  void _openSettings({bool expandServer = false}) {
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => SettingsPage(
            api: _api,
            strings: _strings,
            language: _language,
            themeMode: _themeMode,
            palette: _palette,
            user: _user,
            share: _share,
            onLanguageChanged: _setLanguage,
            onThemeModeChanged: _setThemeMode,
            onPaletteChanged: _setPalette,
            onShareChanged: (share) => setState(() => _share = share),
            onAccountDeleted: _user == null ? null : _onAccountDeleted,
            onLogout: _user == null ? null : _logout,
            onApiBaseChanged: _onApiBaseChanged,
            onConsentRequired: _onOwnConsentRequired,
            onRoleChanged: _user == null ? null : _onRoleChosen,
            onStageChanged: _user == null ? null : _onStageChanged,
            onRemindersToggled: _user == null ? null : _onRemindersToggled,
            dailyReminderSyncQueue: _dailyReminderSyncQueue,
            partnerAlertSyncQueue: _partnerAlertSyncQueue,
            consentPending: _consentRequired,
            expandServer: expandServer,
          ),
        ),
      ),
    );
  }

  Future<void> _dismissReminderHint() async {
    await _prefs.dismissReminderHint();
    if (!mounted) return;
    setState(() => _reminderHintDismissed = true);
  }

  Widget _home() {
    if (_loading) {
      return Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Text(
              _strings.loading,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      );
    }
    if (_api.config.needsServerSetup) {
      return ServerSetupScreen(
        api: _api,
        strings: _strings,
        onConnected: _onServerConnected,
        onOpenGuide: _openSelfHostGuide,
        onOpenSettings: _openSettings,
      );
    }
    if (_user == null) {
      return AuthScreen(
        strings: _strings,
        customServer: _api.config.usesCustomApiBase
            ? Uri.tryParse(_api.config.apiBaseUrl)?.authority
            : null,
        onSignIn: _signIn,
        onOpenSettings: _openSettings,
        // Server choice happens before sign-in; web always uses its origin.
        // Builds without a built-in server switch on the setup screen.
        onOpenServerSettings: kIsWeb
            ? null
            : _api.config.hasDefaultServer
                ? () => _openSettings(expandServer: true)
                : _openServerSetup,
      );
    }
    if (_consentRequired) {
      return ConsentScreen(
        api: _api,
        strings: _strings,
        version: _consentVersion,
        onAccepted: _onConsented,
        onNoticeChanged: (version) async {
          unawaited(_cancelDailyReminder());
          unawaited(_cancelPartnerAlerts());
          try {
            await _refreshConsentSession();
          } catch (_) {}
          if (mounted) {
            setState(() {
              _consentRequired = true;
              _consentVersion = version;
            });
          }
        },
        onDecline: _logout,
        onOpenSettings: _openSettings,
      );
    }
    if (!_user!.hasRole) {
      return RoleChoiceScreen(
        api: _api,
        strings: _strings,
        onChosen: _onRoleChosen,
        onOpenSettings: _openSettings,
      );
    }
    if (_user!.isPartner && !_share.isActive) {
      return PartnerJoinScreen(
        api: _api,
        strings: _strings,
        revoked: _share.isRevoked,
        onJoined: _onJoinedCalendar,
        onAccountDeleted: _onAccountDeleted,
        onOpenSettings: _openSettings,
        // Allowed while unlinked, in case the wrong role was picked.
        onSwitchToOwner: _switchToOwner,
      );
    }
    return CalendarScreen(
      api: _api,
      user: _user!,
      share: _share,
      strings: _strings,
      palette: _palette,
      onOpenSettings: _openSettings,
      cycleRefreshSignal: _stageChanges,
      onShareChanged: (share) => setState(() => _share = share),
      onConsentRequired: _onOwnConsentRequired,
      partnerAlertSyncQueue: _partnerAlertSyncQueue,
      cancelDailyReminder: () async {
        await _cancelDailyReminder();
        return const LocalReminderSyncResult(
          LocalReminderSyncStatus.cancelled,
        );
      },
      // Partners get alerts instead of a daily reminder, so no bubble for them.
      showReminderHint: _user!.isOwner &&
          _remindersOn == false &&
          !_reminderHintDismissed &&
          _share.canEditCalendar,
      onDismissReminderHint: _dismissReminderHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '217',
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: buildApp217Theme(
        brightness: Brightness.light,
        palette: _palette,
      ),
      darkTheme: buildApp217Theme(
        brightness: Brightness.dark,
        palette: _palette,
      ),
      home: _home(),
    );
  }
}

class _ChangeTicker extends ChangeNotifier {
  void notify() => notifyListeners();
}
