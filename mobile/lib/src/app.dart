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
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
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
      await _api.loadPersistedApiBase();
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
    setState(() => _user = null);
  }

  void _openSettings() {
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          api: _api,
          strings: _strings,
          portuguese: _portuguese,
          themeMode: _themeMode,
          onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
          onToggleTheme: () => setState(() {
            _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }),
          onLogout: _user == null ? null : _logout,
          onApiBaseChanged: () => setState(() {}),
        ),
      ),
    );
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
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
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
                  apiBaseUrl: _api.config.apiBaseUrl,
                  onSignIn: _signIn,
                  onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
                  onOpenSettings: _openSettings,
                )
              : CalendarScreen(
                  api: _api,
                  user: _user!,
                  strings: _strings,
                  onLogout: _logout,
                  onOpenSettings: _openSettings,
                ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.strings,
    required this.portuguese,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onToggleTheme,
    required this.onApiBaseChanged,
    this.onLogout,
  });

  final ApiClient api;
  final Strings strings;
  final bool portuguese;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;
  final VoidCallback onApiBaseChanged;
  final Future<void> Function()? onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiBase =
      TextEditingController(text: widget.api.config.apiBaseUrl);
  bool _testing = false;

  @override
  void dispose() {
    _apiBase.dispose();
    super.dispose();
  }

  Future<void> _saveApiBase() async {
    try {
      await widget.api.setApiBaseUrl(_apiBase.text);
      widget.onApiBaseChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.save)),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      await widget.api.setApiBaseUrl(_apiBase.text);
      widget.onApiBaseChanged();
      final ok = await widget.api.ping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? widget.strings.connectionOk : widget.strings.connectionFail)),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.strings.apiBaseUrl, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _apiBase,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: widget.strings.apiBaseHint,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: _saveApiBase, child: Text(widget.strings.save)),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                child: Text(widget.strings.testConnection),
              ),
            ],
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.strings.language),
            subtitle: Text(widget.portuguese ? 'Português' : 'English'),
            onTap: widget.onToggleLanguage,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.strings.darkMode),
            value: widget.themeMode == ThemeMode.dark,
            onChanged: (_) => widget.onToggleTheme(),
          ),
          if (widget.onLogout != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.strings.logout),
              onTap: () async {
                await widget.onLogout!();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
