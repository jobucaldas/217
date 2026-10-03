import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../platform/open_url.dart';
import '../theme/app_theme.dart';
import 'partner_alerts_screen.dart';
import 'reminder_settings_screen.dart';
import 'role_screen.dart';
import 'share_screens.dart';

/// Grouped inset settings (Material 3 / iOS Settings style).
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.strings,
    required this.language,
    required this.themeMode,
    required this.palette,
    required this.onLanguageChanged,
    required this.onThemeModeChanged,
    required this.onPaletteChanged,
    required this.onApiBaseChanged,
    this.user,
    this.share,
    this.onShareChanged,
    this.onAccountDeleted,
    this.onLogout,
    this.onRoleChanged,
    this.onRemindersToggled,
    this.expandServer = false,
  });

  final ApiClient api;
  final Strings strings;
  final AppLanguage language;
  final ThemeMode themeMode;
  final AppPalette palette;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<AppPalette> onPaletteChanged;
  final VoidCallback onApiBaseChanged;
  final User? user;
  final ShareState? share;
  final ValueChanged<ShareState>? onShareChanged;
  final VoidCallback? onAccountDeleted;
  final Future<void> Function()? onLogout;

  /// Called after an owner with nothing shared switched to partner.
  final ValueChanged<SessionSnapshot>? onRoleChanged;

  /// Called after the reminder switch was saved, with its new value.
  final ValueChanged<bool>? onRemindersToggled;

  /// Open with the self-hosted server field already expanded.
  final bool expandServer;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Empty field = default server; only a self-hosted URL is shown here.
  late final TextEditingController _serverUrl = TextEditingController(
    text:
        widget.api.config.usesCustomApiBase ? widget.api.config.apiBaseUrl : '',
  );
  late bool _advancedOpen =
      widget.expandServer || widget.api.config.usesCustomApiBase;
  bool _testing = false;
  String? _serverError;

  @override
  void dispose() {
    _serverUrl.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveServer() async {
    try {
      ApiClient.parseApiBase(_serverUrl.text);
    } on FormatException {
      setState(() => _serverError = widget.strings.serverInvalid);
      return;
    }
    final changed = await widget.api.setApiBaseUrl(_serverUrl.text);
    if (!mounted) return;
    final custom = widget.api.config.usesCustomApiBase;
    setState(() {
      _serverError = null;
      _serverUrl.text = custom ? widget.api.config.apiBaseUrl : '';
    });
    if (changed) widget.onApiBaseChanged();
    _showSnack(
        custom ? widget.strings.serverSaved : widget.strings.serverReset);
  }

  Future<void> _openGuide() async {
    if (await openExternalUrl(selfHostGuideUrl)) return;
    await Clipboard.setData(const ClipboardData(text: selfHostGuideUrl));
    if (mounted) _showSnack(widget.strings.linkCopied);
  }

  /// Probes the typed URL (or the default when empty) without saving it.
  Future<void> _testServer() async {
    final String base;
    try {
      final parsed = ApiClient.parseApiBase(_serverUrl.text);
      base = parsed.isEmpty ? widget.api.config.defaultApiBaseUrl : parsed;
    } on FormatException {
      setState(() => _serverError = widget.strings.serverInvalid);
      return;
    }
    setState(() {
      _testing = true;
      _serverError = null;
    });
    final check = await widget.api.checkServer(baseUrl: base);
    if (!mounted) return;
    setState(() => _testing = false);
    _showSnack(switch (check) {
      ServerCheck.ok => widget.strings.connectionOk,
      ServerCheck.unreachable => widget.strings.serverUnreachable,
      ServerCheck.notA217Server => widget.strings.connectionFail,
      ServerCheck.signInNotConfigured => widget.strings.serverSignInOff,
    });
  }

  String _paletteLabel(AppPalette p) {
    switch (p) {
      case AppPalette.blue:
        return widget.strings.paletteBlue;
      case AppPalette.cyan:
        return widget.strings.paletteCyan;
      case AppPalette.purple:
        return widget.strings.palettePurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.onLogout != null) ...[
            _SettingsSection(
              children: [
                if (widget.user?.isPartner ?? false)
                  ListTile(
                    key: const ValueKey('settings-partner-alerts'),
                    title: Text(widget.strings.partnerAlerts),
                    subtitle: Text(widget.strings.partnerAlertsSubtitle),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PartnerAlertsScreen(
                            api: widget.api,
                            strings: widget.strings,
                            share: widget.share ??
                                const ShareState(status: 'none'),
                          ),
                        ),
                      );
                    },
                  )
                else
                  ListTile(
                    title: Text(widget.strings.reminders),
                    subtitle: Text(widget.strings.reminderEnable),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReminderSettingsScreen(
                            api: widget.api,
                            strings: widget.strings,
                            onToggled: widget.onRemindersToggled,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _SectionLabel(widget.strings.appearance),
          _SettingsSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
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
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.strings.colorTheme,
                    style: text.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in AppPalette.values)
                      ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: p.swatch,
                          radius: 7,
                        ),
                        label: Text(_paletteLabel(p)),
                        selected: widget.palette == p,
                        onSelected: (_) => widget.onPaletteChanged(p),
                        selectedColor: scheme.primaryContainer,
                        backgroundColor: scheme.surface,
                        labelStyle: text.labelLarge?.copyWith(
                          color: widget.palette == p
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                        side: BorderSide(
                          color: widget.palette == p
                              ? scheme.primary.withValues(alpha: 0.55)
                              : scheme.outline.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(widget.strings.languageLabel),
          _SettingsSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: DropdownMenu<AppLanguage>(
                  key: ValueKey(widget.language),
                  initialSelection: widget.language,
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final language in AppLanguage.values)
                      DropdownMenuEntry(
                        value: language,
                        label: language.nativeName,
                      ),
                  ],
                  onSelected: (value) {
                    if (value == null) return;
                    widget.onLanguageChanged(value);
                  },
                ),
              ),
            ],
          ),
          if (widget.user != null &&
              widget.user!.isOwner &&
              widget.share != null &&
              widget.onShareChanged != null) ...[
            const SizedBox(height: 20),
            ShareSettingsSection(
              api: widget.api,
              strings: widget.strings,
              user: widget.user!,
              share: widget.share!,
              onShareChanged: widget.onShareChanged!,
            ),
            // Picked the wrong role: only while nothing is shared.
            if (widget.share!.isNone && widget.onRoleChanged != null) ...[
              const SizedBox(height: 12),
              _SettingsSection(
                children: [
                  ListTile(
                    key: const ValueKey('settings-switch-partner'),
                    title: Text(widget.strings.switchToPartner),
                    trailing: Icon(
                      Icons.swap_horiz,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () async {
                      final session = await confirmRoleSwitch(
                        context: context,
                        api: widget.api,
                        strings: widget.strings,
                        role: 'partner',
                      );
                      if (session == null || !context.mounted) return;
                      widget.onRoleChanged!(session);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ],
          // Signed out only: the server is picked before signing in, since
          // an account lives on one server. Never on web, which is served by
          // its own server (same origin, CORS-locked). Builds without a
          // built-in server pick it on the server setup screen instead.
          if (!kIsWeb &&
              widget.user == null &&
              widget.api.config.hasDefaultServer) ...[
            const SizedBox(height: 20),
            _SettingsSection(
              children: [
                ListTile(
                  title: Text(
                    _advancedOpen
                        ? widget.strings.showLess
                        : widget.strings.showMore,
                    style: text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                  trailing: Icon(
                    _advancedOpen ? Icons.expand_less : Icons.expand_more,
                    color: scheme.primary,
                  ),
                  onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                ),
                if (_advancedOpen) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      key: const ValueKey('server-url'),
                      controller: _serverUrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveServer(),
                      onChanged: (_) {
                        if (_serverError != null) {
                          setState(() => _serverError = null);
                        }
                      },
                      style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                      decoration: InputDecoration(
                        labelText: widget.strings.serverUrl,
                        hintText: widget.api.config.defaultApiBaseUrl,
                        helperText: widget.strings.serverUrlHelp,
                        helperMaxLines: 3,
                        helperStyle: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        errorText: _serverError,
                        errorMaxLines: 2,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: _saveServer,
                            child: Text(widget.strings.save),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              foregroundColor: scheme.onSurface,
                              side: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.8),
                              ),
                            ),
                            onPressed: _testing ? null : _testServer,
                            child: _testing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(widget.strings.testConnection),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
          // Signed in or out, on web too: where to run your own server.
          const SizedBox(height: 20),
          _SettingsSection(
            children: [
              ListTile(
                key: const ValueKey('self-host-guide'),
                leading: Icon(Icons.dns_outlined, color: scheme.primary),
                title: Text(widget.strings.selfHostGuide),
                subtitle: Text(widget.strings.selfHostBlurb),
                trailing:
                    Icon(Icons.open_in_new, color: scheme.onSurfaceVariant),
                onTap: _openGuide,
              ),
            ],
          ),
          // Account actions: pull away from prefs above; keep delete + logout tight.
          if (widget.onAccountDeleted != null || widget.onLogout != null) ...[
            const SizedBox(height: 40),
            if (widget.onAccountDeleted != null)
              DeleteAccountSection(
                api: widget.api,
                strings: widget.strings,
                onAccountDeleted: () {
                  widget.onAccountDeleted!();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            if (widget.onAccountDeleted != null && widget.onLogout != null)
              const SizedBox(height: 10),
            if (widget.onLogout != null)
              _SettingsSection(
                children: [
                  ListTile(
                    title: Text(
                      widget.strings.logout,
                      style: text.bodyLarge?.copyWith(
                        color: kLogoutActionColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () async {
                      await widget.onLogout!();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}
