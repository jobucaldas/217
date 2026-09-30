import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'reminder_settings_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.api,
    required this.user,
    required this.strings,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final ApiClient api;
  final User user;
  final Strings strings;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenSettings;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  Map<String, Entry> _entries = {};
  bool _loading = true;
  String? _error;
  String _reminderSummary = '';

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.api.listEntries(_month.year, _month.month);
      String reminder = widget.strings.reminderNotReady;
      try {
        final pref = await widget.api.getReminderPreference();
        if (pref != null) {
          reminder = pref.enabled
              ? (pref.deliverable
                  ? '${widget.strings.remindersOn} · ${pref.time}'
                  : widget.strings.reminderNotReady)
              : widget.strings.remindersOff;
        }
      } catch (_) {
        // Reminders are optional; calendar still works.
      }
      if (!mounted) return;
      setState(() {
        _entries = {for (final e in entries) e.date: e};
        _reminderSummary = reminder;
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

  Future<void> _openDay(DateTime day) async {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final existing = _entries[key];
    final result = await showModalBottomSheet<_DayEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DayEditor(
        strings: widget.strings,
        date: key,
        initialTaken: existing?.taken,
        initialNotes: existing?.notes ?? '',
      ),
    );
    if (result == null) return;
    await widget.api.upsertEntry(key, taken: result.taken, notes: result.notes);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.pt ? 'pt_BR' : 'en_US';
    final monthLabel = DateFormat.yMMMM(locale).format(_month);
    final todayKey = DateFormat('yyyy-MM-dd').format(_today);
    final todayEntry = _entries[todayKey];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final todayStatus = todayEntry == null
        ? widget.strings.unrecorded
        : (todayEntry.taken ? widget.strings.taken : widget.strings.missed);
    final todayColor = todayEntry == null
        ? scheme.onSurfaceVariant
        : (todayEntry.taken ? App217Colors.taken : App217Colors.missed);
    final humanDate = DateFormat.MMMMd(locale).format(_today);
    final primaryLabel =
        todayEntry == null ? widget.strings.recordToday : widget.strings.updateToday;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.brand),
        actions: [
          IconButton(
            tooltip: widget.strings.settings,
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: widget.strings.logout,
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One job: today's intake — status + single primary action.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.strings.today,
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(humanDate, style: text.headlineMedium),
                    ),
                    Text(
                      todayStatus,
                      style: text.titleLarge?.copyWith(color: todayColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReminderSettingsScreen(
                          api: widget.api,
                          strings: widget.strings,
                        ),
                      ),
                    );
                    if (mounted) await _load();
                  },
                  child: Text(
                    _reminderSummary.isEmpty
                        ? widget.strings.reminderNotReady
                        : _reminderSummary,
                    style: text.bodyMedium?.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => _openDay(_today),
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                _LegendDot(color: App217Colors.taken, label: widget.strings.legendTaken),
                const SizedBox(width: 14),
                _LegendDot(color: App217Colors.missed, label: widget.strings.legendMissed),
                const SizedBox(width: 14),
                _LegendDot(
                  color: scheme.outline,
                  label: widget.strings.legendUnrecorded,
                  outlined: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: monthLabel,
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month - 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month + 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: _MonthGrid(
              month: _month,
              today: _today,
              entries: _entries,
              onDayTap: _openDay,
              todayLabel: widget.strings.today,
              portuguese: widget.strings.pt,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.entries,
    required this.onDayTap,
    required this.todayLabel,
    required this.portuguese,
  });

  final DateTime month;
  final DateTime today;
  final Map<String, Entry> entries;
  final Future<void> Function(DateTime day) onDayTap;
  final String todayLabel;
  final bool portuguese;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sunday-first
    final weekdayLabels = portuguese
        ? const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
        : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cells = <Widget>[
      for (final label in weekdayLabels)
        Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: DateTime(month.year, month.month, day),
          today: today,
          todayLabel: todayLabel,
          entry: entries[DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, day))],
          onTap: onDayTap,
        ),
    ];
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      crossAxisCount: 7,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.todayLabel,
    required this.entry,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final String todayLabel;
  final Entry? entry;
  final Future<void> Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? bg;
    if (entry != null) {
      bg = entry!.taken ? App217Colors.taken : App217Colors.missed;
    }
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    final isFuture = day.isAfter(today);
    return InkWell(
      onTap: isFuture ? null : () => onTap(day),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bg ?? scheme.surface.withValues(alpha: isFuture ? 0.25 : 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? App217Colors.forest : scheme.outline.withValues(alpha: 0.4),
            width: isToday ? 2.2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: bg == null ? scheme.onSurface : Colors.white,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            if (isToday)
              Text(
                todayLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: bg == null ? App217Colors.forest : Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayEditResult {
  const _DayEditResult({required this.taken, required this.notes});
  final bool taken;
  final String notes;
}

class _DayEditor extends StatefulWidget {
  const _DayEditor({
    required this.strings,
    required this.date,
    required this.initialTaken,
    required this.initialNotes,
  });

  final Strings strings;
  final String date;
  final bool? initialTaken;
  final String initialNotes;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late bool? _taken = widget.initialTaken;
  late final TextEditingController _notes = TextEditingController(text: widget.initialNotes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.pt ? 'pt_BR' : 'en_US';
    final human = DateFormat.yMMMMd(locale).format(DateTime.parse(widget.date));
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(human, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            widget.strings.pickStatus,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(value: true, label: Text(widget.strings.takenLabel)),
              ButtonSegment(value: false, label: Text(widget.strings.missedLabel)),
            ],
            selected: {if (_taken != null) _taken!},
            onSelectionChanged: (value) => setState(() => _taken = value.isEmpty ? null : value.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: widget.strings.notes,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _taken == null
                ? null
                : () => Navigator.pop(
                      context,
                      _DayEditResult(taken: _taken!, notes: _notes.text.trim()),
                    ),
            child: Text(widget.strings.save),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.strings.cancel),
          ),
        ],
      ),
    );
  }
}
