import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../theme/app_theme.dart';
import 'reminder_settings_screen.dart';

/// Grouped inset settings (Material 3 / iOS Settings style).
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.strings,
    required this.portuguese,
    required this.themeMode,
    required this.palette,
    required this.onPortugueseChanged,
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
  final ValueChanged<bool> onPortugueseChanged;
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
  bool _advancedOpen = false;

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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.onLogout != null) ...[
            _SettingsSection(
              children: [
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
          _SectionLabel(widget.strings.language),
          _SettingsSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(widget.strings.languagePortuguese),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(widget.strings.languageEnglish),
                    ),
                  ],
                  selected: {widget.portuguese},
                  onSelectionChanged: (value) =>
                      widget.onPortugueseChanged(value.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            children: [
              if (!_advancedOpen)
                ListTile(
                  title: Text(
                    widget.strings.showMore,
                    style: text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                  trailing: Icon(
                    Icons.expand_more,
                    color: scheme.primary,
                  ),
                  onTap: () => setState(() => _advancedOpen = true),
                )
              else ...[
                ListTile(
                  title: Text(
                    widget.strings.showLess,
                    style: text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                  trailing: Icon(
                    Icons.expand_less,
                    color: scheme.primary,
                  ),
                  onTap: () => setState(() => _advancedOpen = false),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _apiBase,
                    keyboardType: TextInputType.url,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: widget.strings.apiBaseUrl,
                      helperText: widget.strings.apiBaseHint,
                      helperMaxLines: 2,
                      helperStyle: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                          onPressed: _saveApiBase,
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
                          onPressed: _testing ? null : _testConnection,
                          child: Text(widget.strings.testConnection),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 28),
            _SettingsSection(
              children: [
                ListTile(
                  title: Text(
                    widget.strings.logout,
                    style: text.titleMedium?.copyWith(color: scheme.error),
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
