import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api/client.dart';
import 'auth/sign_in.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'notifications/local_reminders.dart';
import 'notifications/daily_reminder_sync_queue.dart';
import 'notifications/owner_reminder_repeat_sync.dart';
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
import 'updates/update_check.dart';

class App217 extends StatefulWidget {
  const App217({
    super.key,
    required this.config,
    this.api,
    this.dailyReminderScheduler,
    this.partnerAlertCanceller,
    this.partnerAlertScheduler,
    this.updateClient,
    this.installedVersion,
  });

  final AppConfig config;

  /// Injected client for tests; production builds one from [config].
  final ApiClient? api;
  final DailyReminderScheduler? dailyReminderScheduler;
  final Future<void> Function()? partnerAlertCanceller;
  final PartnerAlertScheduler? partnerAlertScheduler;

  /// Injected HTTP client for the update check; tests pass a mock.
  final http.Client? updateClient;

  /// Installed release tag; tests pass an older one. Defaults to [appVersion].
  final String? installedVersion;

  @override
  State<App217> createState() => _App217State();
}

class _App217State extends State<App217> with WidgetsBindingObserver {
  late final ApiClient _api = (widget.api ?? ApiClient(widget.config))
    ..onConsentRequired = _onOwnConsentRequired;
  late final AppearancePrefs _prefs = AppearancePrefs();
  late final http.Client _updateHttp = widget.updateClient ?? http.Client();
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

  /// Android opt-in: look for a newer APK when the signed-in shell opens.
  bool _autoUpdate = false;
  bool _updateChecked = false;

  /// Local "new message" notifications (Android); on unless turned off.
  bool _messageNotifs = true;

  /// No server push: messages are checked on open/resume and every
  /// [_messagePollEvery] while the app is in the foreground.
  static const _messagePollEvery = Duration(minutes: 2);
  Timer? _messagePoll;
  bool _foreground = true;
  Future<void> _messageChain = Future.value();

  /// Whether the daily reminder is on; null until known (no bubble then).
  bool? _remindersOn;
  int _sessionGeneration = 0;

  /// Changes only when the signed-in account does (logout, deletion, server
  /// switch, sign-in), so a late session refresh cannot restore the old one.
  int _accountEpoch = 0;

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
    WidgetsBinding.instance.addObserver(this);
    _messagePoll = Timer.periodic(_messagePollEvery, (_) => _checkMessages());
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_checkMessages());
  }

  /// Fetches the inbox: refreshes the unread badge and notifies messages
  /// that arrived since the last check. Best effort, silent on failure.
  Future<void> _checkMessages() async {
    final user = _user;
    if (!mounted || !_foreground || user == null || !user.hasRole) return;
    if (_consentRequired || (user.isPartner && !_share.isActive)) return;
    // An open conversation refreshes (and marks read) on its own.
    if (InboxScreen.isOpen) return;
    final epoch = _accountEpoch;
    try {
      final messages = await _api.listInbox();
      if (!mounted || epoch != _accountEpoch || _user?.id != user.id) return;
      await _onMessagesSynced(user.id, messages, notify: true);
    } catch (_) {}
  }

  /// One sync at a time, so the same message is never announced twice.
  Future<void> _onMessagesSynced(
    String userId,
    List<InboxMessage> messages, {
    bool notify = false,
  }) {
    final unread = messages.where((m) => m.isUnread).length;
    if (_user?.id == userId && unread != _share.unreadNotes) {
      setState(() => _share = _share.withUnread(unread));
    }
    return _messageChain = _messageChain.then((_) async {
      try {
        final upTo = await _prefs.messagesNotifiedUpTo(userId);
        // First check on this device: start from here, no backlog alert.
        if (notify && upTo != null && _messageNotifs && _user?.id == userId) {
          final fresh = unannouncedMessages(messages, upTo);
          if (fresh.isNotEmpty) {
            final text = messageNotificationText(_strings, fresh);
            await showMessageNotification(title: text.title, body: text.body);
          }
        }
        // An empty first check still sets the starting point, so the
        // first message that arrives later is announced.
        final newest = newestReceived(messages, upTo) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (newest != upTo) {
          await _prefs.saveMessagesNotifiedUpTo(userId, newest);
        }
      } catch (_) {}
    });
  }

  /// Message notifications are on by default, so the permission (Android
  /// 13+) is asked once, the first time the user opens Messages: a moment
  /// where a prompt about messages makes sense.
  Future<void> _askMessagePermissionOnce() async {
    if (!_messageNotifs || !supportsLocalReminders) return;
    try {
      if (await _prefs.messagePermissionAsked()) return;
      await _prefs.saveMessagePermissionAsked();
      await requestNotificationPermission();
    } catch (_) {}
  }

  Future<void> _setMessageNotifs(bool enabled) async {
    setState(() => _messageNotifs = enabled);
    await _prefs.saveMessageNotifications(enabled);
    if (enabled) await requestNotificationPermission();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.notify();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagePoll?.cancel();
    _changes.dispose();
    _stageChanges.dispose();
    if (widget.updateClient == null) _updateHttp.close();
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
      final autoUpdate = await _prefs.autoUpdateEnabled();
      final messageNotifs = await _prefs.messageNotificationsEnabled();
      if (!mounted) return;
      setState(() {
        _themeMode = appearance.mode;
        _palette = appearance.palette;
        _language = language ?? _deviceLanguage();
        _reminderHintDismissed = hintGone;
        _autoUpdate = autoUpdate;
        _messageNotifs = messageNotifs;
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
      unawaited(_maybeCheckForUpdate());
      unawaited(_checkMessages());
      await _offerPendingInvite();
    }
  }

  /// Once per app start, while signed in and opted in. [force] lets the
  /// switch check right away. Never blocks; failures stay silent.
  Future<void> _maybeCheckForUpdate({bool force = false}) async {
    if (!_autoUpdate || _user == null || !isAndroidPlatform) return;
    if (_updateChecked && !force) return;
    _updateChecked = true;
    final update = await checkForUpdate(
      client: _updateHttp,
      installed: widget.installedVersion ?? appVersion,
    );
    // The user may have opted out or signed out while the request was pending.
    if (update == null || !mounted || !_autoUpdate || _user == null) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 15),
        content: Text(_strings.updateAvailable),
        action: SnackBarAction(
          label: _strings.updateAction,
          // The browser downloads the APK; Android then asks to install it.
          onPressed: () => openExternalUrl(update.apkUrl.toString()),
        ),
      ),
    );
  }

  Future<void> _setAutoUpdate(bool enabled) async {
    setState(() => _autoUpdate = enabled);
    await _prefs.saveAutoUpdate(enabled);
    if (enabled) unawaited(_maybeCheckForUpdate(force: true));
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
    _sessionGeneration++;
    unawaited(_cancelDailyReminder());
    unawaited(_cancelPartnerAlerts());
    unawaited(_recoverConsent());
  }

  Future<void> _refreshSession() async {
    final epoch = _accountEpoch;
    await _api.loadAuthConfig();
    final session = await _api.currentSession();
    if (!mounted || epoch != _accountEpoch) return;
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
    // A message shown for this account must not outlive its session.
    unawaited(cancelMessageNotification());
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
    unawaited(_restoreOwnerReminderAfterConsent(session));
    unawaited(_checkMessages());
    await _offerPendingInvite();
  }

  Future<void> _restoreOwnerReminderAfterConsent(
    SessionSnapshot session,
  ) async {
    final user = session.user;
    if (session.consentRequired || user == null || !user.isOwner) return;
    await _syncOwnerReminder();
  }

  Future<void>? _ownerReminderSync;
  bool _ownerReminderSyncDirty = false;

  /// Re-applies the saved owner reminder (and its "pill not logged" repeat
  /// range) to the OS scheduler from the latest preference and a fresh
  /// "logged today" read. Shared by consent restore, calendar writes and app
  /// resume, so logging today's pill stops today's repeats everywhere, not
  /// just from the settings screen. Concurrent callers (e.g. a consent
  /// restore racing the calendar's own initial load) coalesce into the same
  /// in-flight run. A caller that arrives while one is already running
  /// instead marks it dirty, so exactly one more full run (fresh preference
  /// and fresh "logged today" read) starts right after - otherwise that
  /// caller's state change could join a read that started before it and was
  /// never refreshed. That caller awaits the trailing run rather than the
  /// stale one it missed; a caller that arrives during the trailing run
  /// marks it dirty again rather than being dropped.
  Future<void> _syncOwnerReminder() {
    final inFlight = _ownerReminderSync;
    if (inFlight != null) {
      _ownerReminderSyncDirty = true;
      return inFlight;
    }
    return _ownerReminderSync = _runOwnerReminderSync();
  }

  Future<void> _runOwnerReminderSync() async {
    try {
      await _doSyncOwnerReminder();
      while (_ownerReminderSyncDirty) {
        _ownerReminderSyncDirty = false;
        await _doSyncOwnerReminder();
      }
    } finally {
      _ownerReminderSyncDirty = false;
      _ownerReminderSync = null;
    }
  }

  Future<void> _doSyncOwnerReminder() async {
    final user = _user;
    if (user == null || !user.isOwner || _consentRequired) return;
    // Already known off: no-op without touching the network or the OS
    // scheduler (and so without ever prompting for notification permission
    // from this background path).
    if (_remindersOn == false) return;
    final generation = _sessionGeneration;

    // Consent recovery or a settings cancellation can be mid-flight. Let it
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

      // Unknown whether today is logged: skip repeats rather than risk a
      // spam of reminders fired from a stale assumption.
      var todayLogged = true;
      if (pref!.repeatEnabled) {
        try {
          todayLogged = await fetchTodayLogged(_api);
        } catch (_) {}
      }
      if (!_isCurrentConsentedOwner(user.id, generation) ||
          !_dailyReminderSyncQueue.isCurrent(reminderRevision)) {
        return;
      }

      // Permission denial leaves the saved preference on. The reminder
      // settings screen continues to report permissionDenied on its next load.
      await _dailyReminderSyncQueue.scheduleIfCurrent(
        revision: reminderRevision,
        enabled: true,
        timeHhMm: pref.time,
        title: '217',
        body: _strings.recordToday,
        repeatEnabled: pref.repeatEnabled,
        repeatMinutes: pref.repeatMinutes,
        todayLogged: todayLogged,
      );
    } catch (_) {
      // Best-effort background resync; a failure must not gate the calendar,
      // change the saved preference, or spam retries.
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
    unawaited(_checkMessages());
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
    _accountEpoch++;
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
        _accountEpoch++;
        _sessionGeneration++;
        setState(() {
          _user = session.user ?? user;
          _share = session.share ?? const ShareState(status: 'none');
          _setConsent(session);
          _loading = false;
        });
        if (!_consentRequired) {
          unawaited(_loadRemindersState());
          unawaited(_maybeCheckForUpdate());
          unawaited(_checkMessages());
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
    _accountEpoch++;
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
    _accountEpoch++;
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

  /// Drops in-flight alert plans; cancelling waits for the server to confirm,
  /// so a failed deletion keeps the reminder and alerts.
  void _onAccountDeletionStarted() {
    _sessionGeneration++;
    setState(() {});
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
            onAccountDeleting: _user == null ? null : _onAccountDeletionStarted,
            onAccountDeleted: _user == null ? null : _onAccountDeleted,
            onLogout: _user == null ? null : _logout,
            onApiBaseChanged: _onApiBaseChanged,
            onRoleChanged: _user == null ? null : _onRoleChosen,
            onStageChanged: _user == null ? null : _onStageChanged,
            onRemindersToggled: _user == null ? null : _onRemindersToggled,
            dailyReminderSyncQueue: _dailyReminderSyncQueue,
            partnerAlertSyncQueue: _partnerAlertSyncQueue,
            consentPending: _consentRequired,
            autoUpdate: _autoUpdate,
            onAutoUpdateChanged: _setAutoUpdate,
            messageNotifications: _messageNotifs,
            onMessageNotificationsChanged: _setMessageNotifs,
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
        onAccountDeleting: _onAccountDeletionStarted,
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
      onInboxSynced: (messages) {
        unawaited(_askMessagePermissionOnce());
        _onMessagesSynced(_user!.id, messages);
      },
      partnerAlertSyncQueue: _partnerAlertSyncQueue,
      onOwnerReminderResync: _user!.isOwner ? _syncOwnerReminder : null,
      sessionGeneration: () => _sessionGeneration,
      isSessionCurrent: (generation, userId) =>
          mounted &&
          generation == _sessionGeneration &&
          !_consentRequired &&
          _user?.id == userId,
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
