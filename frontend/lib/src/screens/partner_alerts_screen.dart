import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications/local_reminders.dart';
import '../notifications/partner_alert_sync.dart';

/// Partner notifications: PMS heads-up and pill-not-logged, each with its own
/// toggle and time.
class PartnerAlertsScreen extends StatefulWidget {
  const PartnerAlertsScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.share,
    this.reschedule,
  });

  final ApiClient api;
  final Strings strings;
  final ShareState share;

  /// Replaces OS scheduling (tests); defaults to planning from her calendar.
  final Future<LocalReminderSyncStatus> Function(PartnerAlertPreference)?
      reschedule;

  @override
  State<PartnerAlertsScreen> createState() => _PartnerAlertsScreenState();
}

class _PartnerAlertsScreenState extends State<PartnerAlertsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  PartnerAlertPreference _pref = const PartnerAlertPreference();

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
      final pref = await widget.api.getPartnerAlerts();
      if (!mounted) return;
      setState(() {
        _pref = pref;
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

  Future<void> _save(PartnerAlertPreference next) async {
    final previous = _pref;
    setState(() {
      _pref = next;
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.savePartnerAlerts(next);
      final status = await (widget.reschedule ?? _reschedule)(saved);
      if (!mounted) return;
      setState(() {
        _pref = saved;
        _saving = false;
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
    }
  }

  /// Replans OS notifications from her latest calendar.
  Future<LocalReminderSyncStatus> _reschedule(
    PartnerAlertPreference pref,
  ) async {
    if (!supportsLocalReminders) return LocalReminderSyncStatus.unsupported;
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
      } catch (_) {
        // Schedule what we can (pill alerts don't need the cycle).
      }
    }
    return syncPartnerAlertsFrom(
      strings: widget.strings,
      pref: pref,
      cycle: cycle,
      linked: linked,
      todayLogged: todayLogged,
      ownerName: widget.share.ownerName,
    );
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
        ],
      ),
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
