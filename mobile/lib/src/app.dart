import 'package:flutter/material.dart';

import 'api/client.dart';
import 'auth/sign_in.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'prefs.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_screens.dart';
import 'theme/app_theme.dart';

class App217 extends StatefulWidget {
  const App217({super.key, required this.config});

  final AppConfig config;

  @override
  State<App217> createState() => _App217State();
}

class _App217State extends State<App217> {
  late final ApiClient _api = ApiClient(widget.config);
  late final AppearancePrefs _prefs = AppearancePrefs();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  User? _user;
  ShareState _share = const ShareState(status: 'none');
  bool _loading = true;
  bool _portuguese = true;
  ThemeMode _themeMode = ThemeMode.system;
  AppPalette _palette = AppPalette.azure;
  bool _reminderHintDismissed = false;

  Strings get _strings => Strings(_portuguese);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final appearance = await _prefs.load();
      final hintGone = await _prefs.reminderHintDismissed();
      await _api.loadPersistedApiBase();
      final session = await _api.currentSession();
      if (!mounted) return;
      setState(() {
        _themeMode = appearance.mode;
        _palette = appearance.palette;
        _reminderHintDismissed = hintGone;
        _user = session.user;
        _share = session.share ?? const ShareState(status: 'none');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _share = const ShareState(status: 'none');
        _loading = false;
      });
    }
  }

  Future<void> _refreshSession() async {
    final session = await _api.currentSession();
    if (!mounted) return;
    setState(() {
      _user = session.user;
      _share = session.share ?? const ShareState(status: 'none');
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _prefs.saveThemeMode(mode);
  }

  Future<void> _setPalette(AppPalette palette) async {
    setState(() => _palette = palette);
    await _prefs.savePalette(palette);
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final user = await beginWorkOSSignIn(_api);
      if (!mounted) return;
      if (user != null) {
        final session = await _api.currentSession();
        if (!mounted) return;
        setState(() {
          _user = session.user ?? user;
          _share = session.share ?? const ShareState(status: 'none');
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _loading = false);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${_strings.signInError}\n$err')),
      );
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    setState(() {
      _user = null;
      _share = const ShareState(status: 'none');
    });
  }

  void _onAccountDeleted() {
    setState(() {
      _user = null;
      _share = const ShareState(status: 'none');
    });
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(_strings.accountDeleted)),
    );
  }

  void _openSettings() {
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          api: _api,
          strings: _strings,
          portuguese: _portuguese,
          themeMode: _themeMode,
          palette: _palette,
          user: _user,
          share: _share,
          onPortugueseChanged: (pt) => setState(() => _portuguese = pt),
          onThemeModeChanged: _setThemeMode,
          onPaletteChanged: _setPalette,
          onShareChanged: (share) => setState(() => _share = share),
          onAccountDeleted: _onAccountDeleted,
          onLogout: _user == null ? null : _logout,
          onApiBaseChanged: () => setState(() {}),
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
    if (_user == null) {
      return AuthScreen(
        strings: _strings,
        apiBaseUrl: _api.config.apiBaseUrl.isEmpty
            ? 'same-origin'
            : _api.config.apiBaseUrl,
        onSignIn: _signIn,
        onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
        onOpenSettings: _openSettings,
        showReminderHint: !_reminderHintDismissed,
        onDismissReminderHint: _dismissReminderHint,
      );
    }
    if (_user!.isPartner && _share.isRevoked) {
      return PartnerRevokedScreen(
        api: _api,
        strings: _strings,
        onJoined: (share) {
          setState(() => _share = share);
          _refreshSession();
        },
        onAccountDeleted: _onAccountDeleted,
        onOpenSettings: _openSettings,
      );
    }
    return CalendarScreen(
      api: _api,
      user: _user!,
      share: _share,
      strings: _strings,
      palette: _palette,
      onLogout: _logout,
      onOpenSettings: _openSettings,
      onShareChanged: (share) => setState(() => _share = share),
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
