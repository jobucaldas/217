import 'dart:async';

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
  static const _repeatMinutesSaveDebounce = Duration(milliseconds: 700);

  bool _loading = true;
  bool _saving = false;
  int _inFlightSaves = 0;
  Future<void> _saveChain = Future.value();
  String? _error;
  String? _calendarDataError;
  bool _pmsSuppressed = false;
  PartnerAlertPreference _pref = const PartnerAlertPreference();
  final _repeatMinutesController = TextEditingController();
  final _repeatMinutesFocusNode = FocusNode();
  Timer? _repeatMinutesSaveTimer;
  int? _pendingRepeatMinutes;
  String? _repeatError;

  @override
  void initState() {
    super.initState();
    _repeatMinutesController.text = _pref.pillRepeatMinutes.toString();
    _repeatMinutesFocusNode.addListener(_onRepeatMinutesFocusChange);
    _load();
  }

  void _cancelRepeatMinutesTimer() {
    _repeatMinutesSaveTimer?.cancel();
    _repeatMinutesSaveTimer = null;
  }

  @override
  void dispose() {
    _cancelRepeatMinutesTimer();
    _repeatMinutesFocusNode.removeListener(_onRepeatMinutesFocusChange);
    _repeatMinutesFocusNode.dispose();
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

  /// Queues the request behind any save already in flight so two writes can
  /// never race on the server or on rolling back `_pref`.
  Future<void> _save(PartnerAlertPreference next) {
    final previous = _pref;
    _inFlightSaves++;
    setState(() {
      _pref = next;
      _saving = true;
      _error = null;
    });
    final run = _saveChain.then((_) => _performSave(next, previous));
    _saveChain = run;
    return run;
  }

  Future<void> _performSave(
    PartnerAlertPreference next,
    PartnerAlertPreference previous,
  ) async {
    final syncQueue = widget.syncQueue;
    final revision = syncQueue?.beginIntent();
    try {
      final saved = await widget.api.savePartnerAlerts(next);
      final status = widget.reschedule != null
          ? await widget.reschedule!(saved)
          : await _reschedule(saved, revision: revision);
      if (!mounted) return;
      setState(() {
        // A newer edit may have landed in `_pref` while this request was in
        // flight; only replace it with the server echo if nothing has.
        if (identical(_pref, next)) _pref = saved;
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
        if (identical(_pref, next)) {
          _pref = previous;
          // A debounced edit newer than this failed save must win: rewriting
          // the controller here would show text for a value that was never
          // sent and drop the pending save that would have fixed it.
          final hasNewerUnflushedEdit =
              _repeatMinutesSaveTimer?.isActive == true ||
                  (_pendingRepeatMinutes != null &&
                      _pendingRepeatMinutes != next.pillRepeatMinutes);
          if (!hasNewerUnflushedEdit) {
            _cancelRepeatMinutesTimer();
            _pendingRepeatMinutes = null;
            _repeatMinutesController.text =
                previous.pillRepeatMinutes.toString();
            _repeatError = null;
          }
        }
        _error = friendlyError(widget.strings, err);
      });
    } finally {
      if (revision != null) syncQueue?.finishIntent(revision);
      _inFlightSaves--;
      if (mounted) setState(() => _saving = _inFlightSaves > 0);
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
    _cancelRepeatMinutesTimer();
    _pendingRepeatMinutes = null;
    setState(() => _repeatError = null);
    if (!enabled) {
      await _save(_pref.copyWith(pillRepeatEnabled: false));
      return;
    }
    final minutes =
        _pref.pillRepeatMinutes >= 1 && _pref.pillRepeatMinutes <= 120
            ? _pref.pillRepeatMinutes
            : 15;
    _repeatMinutesController.text = minutes.toString();
    await _save(
      _pref.copyWith(pillRepeatEnabled: true, pillRepeatMinutes: minutes),
    );
  }

  /// Validates the typed interval; only ever queues a value within 1-120.
  /// Saving is debounced so digits typed in quick succession (e.g. "45")
  /// never get locked out by a save of an earlier, partial digit.
  void _onRepeatMinutesChanged(String value) {
    final minutes = int.tryParse(value);
    if (minutes == null || minutes < 1 || minutes > 120) {
      _cancelRepeatMinutesTimer();
      _pendingRepeatMinutes = null;
      setState(() => _repeatError = widget.strings.pillRepeatRangeError);
      return;
    }
    setState(() => _repeatError = null);
    _pendingRepeatMinutes = minutes;
    _cancelRepeatMinutesTimer();
    _repeatMinutesSaveTimer =
        Timer(_repeatMinutesSaveDebounce, _flushRepeatMinutes);
  }

  void _onRepeatMinutesFocusChange() {
    if (!_repeatMinutesFocusNode.hasFocus) _flushRepeatMinutes();
  }

  /// Sends the latest valid minutes value immediately, cancelling any
  /// pending debounce. A no-op if there is nothing new to save.
  void _flushRepeatMinutes() {
    _cancelRepeatMinutesTimer();
    final minutes = _pendingRepeatMinutes;
    _pendingRepeatMinutes = null;
    if (minutes == null || minutes == _pref.pillRepeatMinutes) return;
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
                    focusNode: _repeatMinutesFocusNode,
                    // Never gated on `_saving`: a save triggered by this
                    // field (or any other control) must not lock out typing.
                    enabled: _pref.pillEnabled,
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
                    onSubmitted: (_) => _flushRepeatMinutes(),
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
