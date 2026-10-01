import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../notifications/local_reminders.dart';

/// Reminder schedule: on/off + time + honest local/push status.
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
  LocalReminderSyncResult? _lastLocal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _statusFor({
    required bool enabled,
    required String time,
    required bool deliverable,
    LocalReminderSyncResult? local,
  }) {
    if (!enabled) return widget.strings.remindersOff;
    if (local?.status == LocalReminderSyncStatus.scheduled) {
      return '${widget.strings.reminderLocalScheduled} · $time';
    }
    if (local?.status == LocalReminderSyncStatus.permissionDenied) {
      return widget.strings.reminderPermissionDenied;
    }
    if (deliverable) {
      return '${widget.strings.reminderReady} · $time';
    }
    if (supportsLocalReminders &&
        local?.status == LocalReminderSyncStatus.unsupported) {
      // Web Notification API present but no background schedule.
      return widget.strings.reminderWebNeedsPush;
    }
    if (supportsLocalReminders) {
      return widget.strings.reminderNeedsPush;
    }
    return widget.strings.reminderUnavailable;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pref = await widget.api.getReminderPreference();
      final vapid = await widget.api.vapidConfig();
      LocalReminderSyncResult? local;
      if (pref != null && pref.enabled && supportsLocalReminders) {
        // Re-assert OS schedule after reboot / reinstall of the app process.
        local = await syncLocalDailyReminder(
          enabled: true,
          timeHhMm: pref.time,
          title: '217',
          body: widget.strings.recordToday,
        );
      }
      if (!mounted) return;
      setState(() {
        _enabled = pref?.enabled ?? false;
        _time = pref?.time ?? '09:00';
        _timezone = pref?.timezone ?? 'UTC';
        _vapidConfigured = vapid.configured;
        _lastLocal = local;
        _status = pref == null
            ? widget.strings.reminderNotReady
            : _statusFor(
                enabled: pref.enabled,
                time: pref.time,
                deliverable: pref.deliverable,
                local: local,
              );
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
      LocalReminderSyncResult? local;
      if (supportsLocalReminders) {
        local = await syncLocalDailyReminder(
          enabled: nextEnabled,
          timeHhMm: _time,
          title: '217',
          body: widget.strings.recordToday,
        );
      }

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
        _lastLocal = local;
        _status = _statusFor(
          enabled: saved.enabled,
          time: saved.time,
          deliverable: saved.deliverable,
          local: local,
        );
        _saving = false;
        if (local?.status == LocalReminderSyncStatus.permissionDenied) {
          _error = widget.strings.reminderPermissionDenied;
        } else if (local?.status == LocalReminderSyncStatus.failed) {
          _error = widget.strings.reminderNeedsPush;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.reminderSaved)),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = (!_vapidConfigured && !supportsLocalReminders)
            ? widget.strings.reminderUnavailable
            : err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final showUnavailable = !_vapidConfigured &&
        !supportsLocalReminders &&
        _lastLocal?.status != LocalReminderSyncStatus.scheduled;
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.reminders)),
      body: _loading
          ? Center(child: Text(widget.strings.loading))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Material(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.strings.reminderNativeNote,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                if (_status != null) Text(_status!, style: text.bodyMedium),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
                if (showUnavailable) ...[
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
