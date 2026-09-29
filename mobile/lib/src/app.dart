import 'package:flutter/material.dart';

import 'api/client.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_screen.dart';

class App217 extends StatefulWidget {
  const App217({super.key, required this.config});

  final AppConfig config;

  @override
  State<App217> createState() => _App217State();
}

class _App217State extends State<App217> {
  late final ApiClient _api = ApiClient(widget.config);
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  User? _user;
  bool _loading = true;
  bool _portuguese = true;
  ThemeMode _themeMode = ThemeMode.dark;

  Strings get _strings => Strings(_portuguese);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final user = await _api.currentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _loading = false;
      });
    }
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final user = await _api.signInWithWorkOS();
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_strings.signInError)),
      );
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F6F5B),
      brightness: _themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      title: '217',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6F5B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _loading
          ? Scaffold(body: Center(child: Text(_strings.loading)))
          : _user == null
              ? AuthScreen(
                  strings: _strings,
                  onSignIn: _signIn,
                  onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
                )
              : CalendarScreen(
                  api: _api,
                  user: _user!,
                  strings: _strings,
                  onLogout: _logout,
                  onOpenSettings: () {
                    _navKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => SettingsPage(
                          strings: _strings,
                          portuguese: _portuguese,
                          themeMode: _themeMode,
                          onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
                          onToggleTheme: () => setState(() {
                            _themeMode = _themeMode == ThemeMode.dark
                                ? ThemeMode.light
                                : ThemeMode.dark;
                          }),
                          onLogout: _logout,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.strings,
    required this.portuguese,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onToggleTheme,
    required this.onLogout,
  });

  final Strings strings;
  final bool portuguese;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        children: [
          ListTile(
            title: Text(strings.language),
            subtitle: Text(portuguese ? 'Português' : 'English'),
            onTap: onToggleLanguage,
          ),
          SwitchListTile(
            title: Text(themeMode == ThemeMode.dark ? 'Dark' : 'Light'),
            value: themeMode == ThemeMode.dark,
            onChanged: (_) => onToggleTheme(),
          ),
          ListTile(
            title: Text(strings.logout),
            onTap: () async {
              await onLogout();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
