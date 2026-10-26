import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications/local_reminders.dart';
import '../notifications/partner_alert_sync.dart';
import '../notifications/partner_alert_sync_queue.dart';

/// Partner notifications: PMS heads-up and pill-not-logged, each with its own
/// toggle and time.
class PartnerAlertsScreen extends StatefulWidget {
  const PartnerAlertsScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.share,
    this.reschedule,
    this.partnerAlertScheduler,
    this.cancelPartnerAlerts,
    this.syncQueue,
  });

  final ApiClient api;
  final Strings strings;
  final ShareState share;

  /// Replaces OS scheduling (tests); defaults to planning from her calendar.
  final Future<LocalReminderSyncStatus> Function(PartnerAlertPreference)?
      reschedule;
  final Future<LocalReminderSyncStatus> Function(List<PlannedAlert>)?
      partnerAlertScheduler;
  final Future<LocalReminderSyncStatus> Function()? cancelPartnerAlerts;
  final PartnerAlertSyncQueue? syncQueue;

  @override
  State<PartnerAlertsScreen> createState() => _PartnerAlertsScreenState();
}

class _PartnerAlertsScreenState extends State<PartnerAlertsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _calendarDataError;
  bool _pmsSuppressed = false;
  PartnerAlertPreference _pref = const PartnerAlertPreference();
  final _repeatMinutesController = TextEditingController();
  String? _repeatError;

  @override
  void initState() {
    super.initState();
    _repeatMinutesController.text = _pref.pillRepeatMinutes.toString();
    _load();
  }

  @override
  void dispose() {
    _repeatMinutesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _calendarDataError = null;
      _pmsSuppressed = false;
    });
    try {
      final pref = await widget.api.getPartnerAlerts();
      if (!mounted) return;
      setState(() {
        _pref = pref;
        _loading = false;
        _repeatError = null;
        _repeatMinutesController.text = pref.pillRepeatMinutes.toString();
      });
    } catch (err) {
      if (err is! ApiException || err.message != 'consent required') {
        await _cancelPartnerAlerts();
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(widget.strings, err);
      });
      return;
    }
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cycle = await widget.api.getCycle(today);
      if (!mounted) return;
      setState(() => _pmsSuppressed = cycle.note == 'pms_suppressed_menopause');
    } catch (err) {
      // Never leave or create reminders based on calendar data that could not
      // be read. The saved preferences remain available for later recovery.
      await _cancelPartnerAlerts();
      if (!mounted) return;
      setState(() {
        _calendarDataError = err is ApiException &&
                err.statusCode == 403 &&
                err.message == 'calendar owner consent required'
            ? widget.strings.sharedCalendarOwnerConsentRequired
            : widget.strings.genericError;
        _error = _calendarDataError;
      });
    }
  }

  Future<void> _save(PartnerAlertPreference next) async {
    final previous = _pref;
    final syncQueue = widget.syncQueue;
    final revision = syncQueue?.beginIntent();
    setState(() {
      _pref = next;
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.savePartnerAlerts(next);
      final status = widget.reschedule != null
          ? await widget.reschedule!(saved)
          : await _reschedule(saved, revision: revision);
      if (!mounted) return;
      setState(() {
        _pref = saved;
        _saving = false;
        _error = _calendarDataError;
        if (status == LocalReminderSyncStatus.permissionDenied) {
          _error = widget.strings.reminderPermissionDenied;
        }
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.strings.reminderSaved)));
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _pref = previous;
        _saving = false;
        _error = friendlyError(widget.strings, err);
      });
    } finally {
      if (revision != null) syncQueue?.finishIntent(revision);
    }
  }

  /// Replans OS notifications from her latest calendar.
  Future<LocalReminderSyncStatus> _reschedule(
    PartnerAlertPreference pref, {
    int? revision,
  }) async {
    if (!supportsLocalReminders &&
        widget.partnerAlertScheduler == null &&
        widget.syncQueue == null) {
      return LocalReminderSyncStatus.unsupported;
    }
    final linked = widget.share.isActive;
    var cycle = CycleInfo.empty;
    var todayLogged = false;
    if (linked) {
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      try {
        cycle = await widget.api.getCycle(today);
        final entries = await widget.api.listEntries(now.year, now.month);
        todayLogged = entries.any((e) => e.date == today && e.taken == true);
      } catch (err) {
        if (err is! ApiException || err.message != 'consent required') {
          await _cancelPartnerAlerts();
        }
        _calendarDataError = err is ApiException &&
                err.statusCode == 403 &&
                err.message == 'calendar owner consent required'
            ? widget.strings.sharedCalendarOwnerConsentRequired
            : widget.strings.genericError;
        return LocalReminderSyncStatus.cancelled;
      }
    }
    final queue = widget.syncQueue;
    if (queue != null && (revision == null || !queue.isCurrent(revision))) {
      return LocalReminderSyncStatus.cancelled;
    }
    final Future<LocalReminderSyncStatus> Function(List<PlannedAlert>)?
        scheduler = queue == null
            ? widget.partnerAlertScheduler
            : (alerts) async =>
                await queue.scheduleIfCurrent(
                  revision: revision!,
                  alerts: alerts,
                ) ??
                LocalReminderSyncStatus.cancelled;
    return syncPartnerAlertsFrom(
      strings: widget.strings,
      pref: pref,
      cycle: cycle,
      linked: linked,
      todayLogged: todayLogged,
      ownerName: widget.share.ownerName,
      scheduler: scheduler,
    );
  }

  Future<LocalReminderSyncStatus> _cancelPartnerAlerts() async {
    final queue = widget.syncQueue;
    if (queue != null) {
      return await queue.cancel() ?? LocalReminderSyncStatus.cancelled;
    }
    return (widget.cancelPartnerAlerts ?? () => syncPartnerAlerts(const []))();
  }

  Future<String?> _pickTime(String current) async {
    final t = parseReminderTime(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
    );
    if (picked == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  Widget _alertCard({
    required Key key,
    required String title,
    required String subtitle,
    required bool enabled,
    required String time,
    required ValueChanged<bool> onToggle,
    required VoidCallback onPickTime,
    Widget? extra,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      key: key,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(title),
            subtitle: Text(subtitle),
            value: enabled,
            onChanged: _saving ? null : onToggle,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            enabled: enabled && !_saving,
            title: Text(widget.strings.reminderTime),
            trailing: Text(
              time,
              style: text.titleLarge?.copyWith(
                color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            onTap: onPickTime,
          ),
          if (extra != null) extra,
        ],
      ),
    );
  }

  /// Turns the pill repeat on/off; a fresh enable seeds the default minutes.
  Future<void> _onToggleRepeat(bool enabled) async {
    setState(() => _repeatError = null);
    if (!enabled) {
      await _save(_pref.copyWith(pillRepeatEnabled: false));
      return;
    }
    final minutes = _pref.pillRepeatMinutes >= 1 && _pref.pillRepeatMinutes <= 120
        ? _pref.pillRepeatMinutes
        : 15;
    _repeatMinutesController.text = minutes.toString();
    await _save(
      _pref.copyWith(pillRepeatEnabled: true, pillRepeatMinutes: minutes),
    );
  }

  /// Validates the typed interval; only ever saves a value within 1-120.
  void _onRepeatMinutesChanged(String value) {
    final minutes = int.tryParse(value);
    if (minutes == null || minutes < 1 || minutes > 120) {
      setState(() => _repeatError = widget.strings.pillRepeatRangeError);
      return;
    }
    setState(() => _repeatError = null);
    _save(_pref.copyWith(pillRepeatMinutes: minutes));
  }

  Widget _pillRepeatSection() {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = _pref.pillEnabled && !_saving;
    final hasError = _repeatError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        SwitchListTile(
          key: const ValueKey('pill-repeat-toggle'),
          title: Text(strings.pillRepeatTitle),
          subtitle: Text(strings.pillRepeatSubtitle),
          value: _pref.pillRepeatEnabled,
          onChanged: enabled ? _onToggleRepeat : null,
        ),
        if (_pref.pillRepeatEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(strings.pillRepeatEveryLabel),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    key: const ValueKey('pill-repeat-minutes-field'),
                    controller: _repeatMinutesController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? scheme.error : scheme.outline,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? scheme.error : scheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onChanged: _onRepeatMinutesChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    strings.pillRepeatMinutesUnit,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_pref.pillRepeatEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              hasError
                  ? _repeatError!
                  : strings.pillRepeatHelper(_pref.pillRepeatMinutes),
              style: text.bodySmall?.copyWith(
                color: hasError ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = widget.strings;
    final note = !supportsLocalReminders || kIsWeb
        ? strings.partnerAlertsWeb
        : !widget.share.isActive
            ? strings.partnerAlertsNeedLink
            : strings.partnerAlertsNote;
    return Scaffold(
      appBar: AppBar(title: Text(strings.partnerAlerts)),
      body: _loading
          ? Center(child: Text(strings.loading))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Material(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      note,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
                if (_pmsSuppressed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(strings.pmsNotCounted,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 16),
                _alertCard(
                  key: const ValueKey('alert-pms'),
                  title: strings.pmsAlertTitle,
                  subtitle: strings.pmsAlertBody,
                  enabled: _pref.pmsEnabled,
                  time: _pref.pmsTime,
                  onToggle: (v) => _save(_pref.copyWith(pmsEnabled: v)),
                  onPickTime: () async {
                    final t = await _pickTime(_pref.pmsTime);
                    if (t != null) await _save(_pref.copyWith(pmsTime: t));
                  },
                ),
                const SizedBox(height: 12),
                _alertCard(
                  key: const ValueKey('alert-pill'),
                  title: strings.pillAlertTitle,
                  subtitle: strings.pillAlertBody,
                  enabled: _pref.pillEnabled,
                  time: _pref.pillTime,
                  onToggle: (v) => _save(_pref.copyWith(pillEnabled: v)),
                  onPickTime: () async {
                    final t = await _pickTime(_pref.pillTime);
                    if (t != null) await _save(_pref.copyWith(pillTime: t));
                  },
                  extra: _pillRepeatSection(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
