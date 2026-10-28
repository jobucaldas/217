import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../notifications/daily_reminder_sync_queue.dart';
import '../notifications/local_reminders.dart';
import '../notifications/owner_reminder_repeat_sync.dart';
import 'repeat_minutes_controller.dart';
import 'repeat_settings_section.dart';

/// Reminder schedule: on/off + time + honest local/push status, plus a
/// "repeat every X minutes until logged" option.
class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    super.key,
    required this.api,
    required this.strings,
    this.dailyReminderSyncQueue,
    this.onToggled,
  });

  final ApiClient api;
  final Strings strings;
  final DailyReminderSyncQueue? dailyReminderSyncQueue;

  /// Called after the on/off switch was saved, with its new value.
  final ValueChanged<bool>? onToggled;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

typedef _ReminderDraft = ({
  bool enabled,
  String time,
  String timezone,
  bool repeatEnabled,
  int repeatMinutes,
});

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  int _inFlightSaves = 0;
  int _draftRevision = 0;
  Future<void> _saveChain = Future.value();
  bool _enabled = false;
  bool _vapidConfigured = false;
  String _time = '09:00';
  String _timezone = 'UTC';
  bool _repeatEnabled = false;
  int _repeatMinutes = 15;
  String? _status;
  String? _error;
  LocalReminderSyncResult? _lastLocal;
  late final _repeatController = RepeatMinutesController(
    currentMinutes: () => _repeatMinutes,
    onFlush: (minutes) => _save(repeatMinutes: minutes),
  );

  @override
  void initState() {
    super.initState();
    _repeatController.attach();
    _load();
  }

  @override
  void dispose() {
    _repeatController.dispose();
    super.dispose();
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
    if (local?.status == LocalReminderSyncStatus.failed) {
      return widget.strings.reminderNeedsPush;
    }
    if (supportsLocalReminders &&
        local?.status == LocalReminderSyncStatus.unsupported) {
      // Web can probe Notification API but cannot schedule background dailies.
      return kIsWeb
          ? widget.strings.reminderWebNeedsPush
          : widget.strings.reminderNeedsPush;
    }
    if (supportsLocalReminders) {
      return widget.strings.reminderNeedsPush;
    }
    return widget.strings.reminderUnavailable;
  }

  /// Unknown whether today is logged: skip repeats rather than risk a spam
  /// of reminders fired from a stale assumption.
  Future<bool> _todayLoggedOrAssumeSo(bool repeatEnabled) async {
    if (!repeatEnabled) return true;
    try {
      return await fetchTodayLogged(widget.api);
    } catch (_) {
      return true;
    }
  }

  Future<void> _load() async {
    final queue = widget.dailyReminderSyncQueue;
    final reminderRevision = queue?.beginIntent();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pref = await widget.api.getReminderPreference();
      final vapid = await widget.api.vapidConfig();
      LocalReminderSyncResult? local;
      if (pref != null && pref.enabled && supportsLocalReminders) {
        final todayLogged = await _todayLoggedOrAssumeSo(pref.repeatEnabled);
        // Re-assert OS schedule after reboot / reinstall of the app process.
        local = queue == null
            ? await syncLocalDailyReminder(
                enabled: true,
                timeHhMm: pref.time,
                title: '217',
                body: widget.strings.recordToday,
                repeatEnabled: pref.repeatEnabled,
                repeatMinutes: pref.repeatMinutes,
                todayLogged: todayLogged,
              )
            : await queue.scheduleIfCurrent(
                revision: reminderRevision!,
                enabled: true,
                timeHhMm: pref.time,
                title: '217',
                body: widget.strings.recordToday,
                repeatEnabled: pref.repeatEnabled,
                repeatMinutes: pref.repeatMinutes,
                todayLogged: todayLogged,
              );
      }
      if (queue != null && !queue.isCurrent(reminderRevision!)) return;
      if (!mounted) return;
      setState(() {
        _enabled = pref?.enabled ?? false;
        _time = pref?.time ?? '09:00';
        _timezone = pref?.timezone ?? 'UTC';
        _repeatEnabled = pref?.repeatEnabled ?? false;
        _repeatMinutes = pref?.repeatMinutes ?? 15;
        _repeatController.textController.text = _repeatMinutes.toString();
        _repeatController.error = null;
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
        _error = friendlyError(widget.strings, err);
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

  _ReminderDraft get _draft => (
        enabled: _enabled,
        time: _time,
        timezone: _timezone,
        repeatEnabled: _repeatEnabled,
        repeatMinutes: _repeatMinutes,
      );

  void _applyDraft(_ReminderDraft draft) {
    _enabled = draft.enabled;
    _time = draft.time;
    _timezone = draft.timezone;
    _repeatEnabled = draft.repeatEnabled;
    _repeatMinutes = draft.repeatMinutes;
  }

  /// Turns the repeat on/off; a fresh enable seeds the default minutes.
  Future<void> _onToggleRepeat(bool enabled) async {
    setState(_repeatController.cancelPending);
    if (!enabled) {
      await _save(repeatEnabled: false);
      return;
    }
    final minutes = validOrDefaultRepeatMinutes(_repeatMinutes);
    _repeatController.textController.text = minutes.toString();
    await _save(repeatEnabled: true, repeatMinutes: minutes);
  }

  /// Queues the save behind any already in flight, so a slow switch/time
  /// save can't race a newer typed minutes value (or vice versa). Applies
  /// [enabled]/[repeatEnabled]/[repeatMinutes] optimistically so the UI
  /// (e.g. the minutes field appearing on enable) doesn't wait on the
  /// network, and rolls back to the pre-save draft on failure unless a
  /// newer save has already superseded this one.
  Future<void> _save({bool? enabled, bool? repeatEnabled, int? repeatMinutes}) {
    final previous = _draft;
    final next = (
      enabled: enabled ?? previous.enabled,
      time: previous.time,
      timezone: previous.timezone.isEmpty ? 'UTC' : previous.timezone,
      repeatEnabled: repeatEnabled ?? previous.repeatEnabled,
      repeatMinutes: repeatMinutes ?? previous.repeatMinutes,
    );
    final attempt = ++_draftRevision;
    final enabledChanged = enabled != null;
    _inFlightSaves++;
    setState(() {
      _applyDraft(next);
      _saving = true;
      _error = null;
      _status = null;
    });
    final run = _saveChain.then(
      (_) => _performSave(next, previous, attempt, enabledChanged),
    );
    _saveChain = run;
    return run;
  }

  Future<void> _performSave(
    _ReminderDraft next,
    _ReminderDraft previous,
    int attempt,
    bool enabledChanged,
  ) async {
    final queue = widget.dailyReminderSyncQueue;
    final reminderRevision = queue?.beginIntent();
    try {
      final saved = await widget.api.upsertReminderPreference(
        enabled: next.enabled,
        time: next.time,
        timezone: next.timezone,
        repeatEnabled: next.repeatEnabled,
        repeatMinutes: next.repeatMinutes,
      );
      final todayLogged = await _todayLoggedOrAssumeSo(saved.repeatEnabled);
      LocalReminderSyncResult? local;
      if (supportsLocalReminders) {
        local = queue == null
            ? await syncLocalDailyReminder(
                enabled: saved.enabled,
                timeHhMm: saved.time,
                title: '217',
                body: widget.strings.recordToday,
                repeatEnabled: saved.repeatEnabled,
                repeatMinutes: saved.repeatMinutes,
                todayLogged: todayLogged,
              )
            : await queue.scheduleIfCurrent(
                revision: reminderRevision!,
                enabled: saved.enabled,
                timeHhMm: saved.time,
                title: '217',
                body: widget.strings.recordToday,
                repeatEnabled: saved.repeatEnabled,
                repeatMinutes: saved.repeatMinutes,
                todayLogged: todayLogged,
              );
      }
      if (queue != null && !queue.isCurrent(reminderRevision!)) return;
      if (!mounted) return;
      setState(() {
        // A newer edit may have landed while this request was in flight;
        // only replace the draft with the server echo if nothing has.
        if (attempt == _draftRevision) {
          _applyDraft((
            enabled: saved.enabled,
            time: saved.time,
            timezone: saved.timezone,
            repeatEnabled: saved.repeatEnabled,
            repeatMinutes: saved.repeatMinutes,
          ));
        }
        _lastLocal = local;
        _status = _statusFor(
          enabled: saved.enabled,
          time: saved.time,
          deliverable: saved.deliverable,
          local: local,
        );
        if (local?.status == LocalReminderSyncStatus.permissionDenied) {
          _error = widget.strings.reminderPermissionDenied;
        } else if (local?.status == LocalReminderSyncStatus.failed) {
          _error = widget.strings.reminderNeedsPush;
        }
      });
      if (enabledChanged) widget.onToggled?.call(saved.enabled);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.strings.reminderSaved)));
    } catch (err) {
      if (!mounted) return;
      setState(() {
        if (attempt == _draftRevision) {
          _applyDraft(previous);
          // A debounced edit newer than this failed save must win: resync
          // only clears the field when there is no newer unflushed edit.
          _repeatController.resyncAfterFailedSave(
            next.repeatMinutes,
            previous.repeatMinutes,
          );
        }
        _error = (!_vapidConfigured && !supportsLocalReminders)
            ? widget.strings.reminderUnavailable
            // 409: the server needs a push subscription to deliver this.
            : err is ApiException && err.statusCode == 409
                ? widget.strings.reminderWebNeedsPush
                : friendlyError(widget.strings, err);
      });
    } finally {
      _inFlightSaves--;
      if (mounted) setState(() => _saving = _inFlightSaves > 0);
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
                  key: const ValueKey('reminder-enable-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.reminderEnable),
                  value: _enabled,
                  onChanged: _saving ? null : (value) => _save(enabled: value),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.strings.reminderTime),
                  subtitle: Text(_time, style: text.headlineMedium),
                  trailing: const Icon(Icons.schedule),
                  onTap: _saving ? null : _pickTime,
                ),
                RepeatSettingsSection(
                  toggleKey: const ValueKey('reminder-repeat-toggle'),
                  fieldKey: const ValueKey('reminder-repeat-minutes-field'),
                  switchTitle: widget.strings.pillRepeatTitle,
                  switchSubtitle: widget.strings.pillRepeatSubtitle,
                  everyLabel: widget.strings.pillRepeatEveryLabel,
                  minutesUnit: widget.strings.pillRepeatMinutesUnit,
                  helperText: widget.strings.reminderRepeatHelper(_repeatMinutes),
                  repeatEnabled: _repeatEnabled,
                  parentEnabled: _enabled,
                  saving: _saving,
                  controller: _repeatController,
                  onToggle: _onToggleRepeat,
                  onMinutesChanged: (value) => setState(
                    () => _repeatController.onChanged(
                      value,
                      rangeErrorText: widget.strings.pillRepeatRangeError,
                    ),
                  ),
                  onMinutesSubmitted: _repeatController.flush,
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
                  Text(widget.strings.reminderUnavailable,
                      style: text.bodyMedium),
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
