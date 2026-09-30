import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n.dart';

/// Skim-friendly reminder schedule: on/off + time + one status line.
class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    super.key,
    required this.api,
    required this.strings,
  });

  final ApiClient api;
  final Strings strings;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _vapidConfigured = false;
  String _time = '09:00';
  String _timezone = 'UTC';
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pref = await widget.api.getReminderPreference();
      final vapid = await widget.api.vapidConfig();
      if (!mounted) return;
      setState(() {
        _enabled = pref?.enabled ?? false;
        _time = pref?.time ?? '09:00';
        _timezone = pref?.timezone ?? 'UTC';
        _vapidConfigured = vapid.configured;
        _status = pref == null
            ? null
            : (pref.deliverable
                ? '${widget.strings.reminderReady} · ${pref.time}'
                : widget.strings.reminderNotReady);
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    }
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save({bool? enabled}) async {
    final nextEnabled = enabled ?? _enabled;
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final tz = _timezone.isEmpty ? 'UTC' : _timezone;
      final saved = await widget.api.upsertReminderPreference(
        enabled: nextEnabled,
        time: _time,
        timezone: tz,
      );
      if (!mounted) return;
      setState(() {
        _enabled = saved.enabled;
        _time = saved.time;
        _timezone = saved.timezone;
        _status = saved.deliverable
            ? '${widget.strings.reminderReady} · ${saved.time}'
            : (saved.enabled
                ? widget.strings.reminderNeedsPush
                : widget.strings.remindersOff);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.reminderSaved)),
      );
    } catch (err) {
      if (!mounted) return;
      final needsPush = err.toString().contains('needs_push');
      setState(() {
        _saving = false;
        _enabled = false;
        _error = needsPush
            ? widget.strings.reminderNeedsPush
            : (!_vapidConfigured
                ? widget.strings.reminderUnavailable
                : err.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.reminders)),
      body: _loading
          ? Center(child: Text(widget.strings.loading))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.reminderEnable),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() => _enabled = value);
                          _save(enabled: value);
                        },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.reminderTime),
                  subtitle: Text(_time, style: text.headlineMedium),
                  trailing: const Icon(Icons.schedule),
                  onTap: _saving ? null : _pickTime,
                ),
                const SizedBox(height: 8),
                if (_status != null)
                  Text(_status!, style: text.bodyMedium),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (!_vapidConfigured) ...[
                  const SizedBox(height: 8),
                  Text(widget.strings.reminderUnavailable, style: text.bodyMedium),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: Text(widget.strings.save),
                ),
              ],
            ),
    );
  }
}
