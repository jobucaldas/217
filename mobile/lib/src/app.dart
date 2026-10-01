import 'package:flutter/material.dart';

import 'api/client.dart';
import 'auth/sign_in.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'prefs.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/reminder_settings_screen.dart';
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
      final user = await _api.currentUser();
      if (!mounted) return;
      setState(() {
        _themeMode = appearance.mode;
        _palette = appearance.palette;
        _reminderHintDismissed = hintGone;
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
        setState(() {
          _user = user;
          _loading = false;
        });
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
          palette: _palette,
          onToggleLanguage: () => setState(() => _portuguese = !_portuguese),
          onThemeModeChanged: _setThemeMode,
          onPaletteChanged: _setPalette,
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
      home: _loading
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: Text(
                    _strings.loading,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            )
          : _user == null
              ? AuthScreen(
                  strings: _strings,
                  apiBaseUrl: _api.config.apiBaseUrl.isEmpty
                      ? 'same-origin'
                      : _api.config.apiBaseUrl,
                  onSignIn: _signIn,
                  onToggleLanguage: () =>
                      setState(() => _portuguese = !_portuguese),
                  onOpenSettings: _openSettings,
                  showReminderHint: !_reminderHintDismissed,
                  onDismissReminderHint: _dismissReminderHint,
                )
              : CalendarScreen(
                  api: _api,
                  user: _user!,
                  strings: _strings,
                  palette: _palette,
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
    required this.palette,
    required this.onToggleLanguage,
    required this.onThemeModeChanged,
    required this.onPaletteChanged,
    required this.onApiBaseChanged,
    this.onLogout,
  });

  final ApiClient api;
  final Strings strings;
  final bool portuguese;
  final ThemeMode themeMode;
  final AppPalette palette;
  final VoidCallback onToggleLanguage;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<AppPalette> onPaletteChanged;
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
        SnackBar(
          content: Text(
            ok ? widget.strings.connectionOk : widget.strings.connectionFail,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _paletteLabel(AppPalette p) {
    switch (p) {
      case AppPalette.azure:
        return widget.strings.paletteAzure;
      case AppPalette.mint:
        return widget.strings.paletteMint;
      case AppPalette.plum:
        return widget.strings.palettePlum;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.onLogout != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.strings.reminders),
              subtitle: Text(widget.strings.reminderEnable),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReminderSettingsScreen(
                      api: widget.api,
                      strings: widget.strings,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 28),
          ],
          Text(widget.strings.appearance,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(widget.strings.themeSystem),
                icon: const Icon(Icons.brightness_auto, size: 18),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(widget.strings.themeLight),
                icon: const Icon(Icons.light_mode_outlined, size: 18),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(widget.strings.themeDark),
                icon: const Icon(Icons.dark_mode_outlined, size: 18),
              ),
            ],
            selected: {widget.themeMode},
            onSelectionChanged: (value) =>
                widget.onThemeModeChanged(value.first),
          ),
          const SizedBox(height: 20),
          Text(widget.strings.colorTheme,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in AppPalette.values)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: p.swatch, radius: 8),
                  label: Text(_paletteLabel(p)),
                  selected: widget.palette == p,
                  onSelected: (_) => widget.onPaletteChanged(p),
                  selectedColor: scheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: widget.palette == p
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
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
          const Divider(height: 28),
          Text(widget.strings.apiBaseUrl,
              style: Theme.of(context).textTheme.titleMedium),
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
              FilledButton(
                onPressed: _saveApiBase,
                child: Text(widget.strings.save),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                child: Text(widget.strings.testConnection),
              ),
            ],
          ),
          if (widget.onLogout != null) ...[
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.strings.logout),
              onTap: () async {
                await widget.onLogout!();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}
