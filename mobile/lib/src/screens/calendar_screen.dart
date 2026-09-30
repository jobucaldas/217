import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';

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
    final label = DateFormat.yMMMM(widget.strings.pt ? 'pt_BR' : 'en_US').format(_month);
    final todayKey = DateFormat('yyyy-MM-dd').format(_today);
    final todayEntry = _entries[todayKey];
    final scheme = Theme.of(context).colorScheme;
    final todayStatus = todayEntry == null
        ? widget.strings.unrecorded
        : (todayEntry.taken ? widget.strings.taken : widget.strings.missed);
    final todayColor = todayEntry == null
        ? scheme.onSurfaceVariant
        : (todayEntry.taken ? App217Colors.taken : App217Colors.missed);

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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.strings.today} · $todayKey',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: todayColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            todayStatus,
                            style: TextStyle(
                              color: todayColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _reminderSummary.isEmpty
                          ? widget.strings.reminderNotReady
                          : _reminderSummary,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _openDay(_today),
                            child: Text(widget.strings.todayStatus),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _month = DateTime(_today.year, _today.month));
                              _load();
                            },
                            child: Text(widget.strings.today),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _LegendChip(color: App217Colors.taken, label: widget.strings.legendTaken),
                _LegendChip(color: App217Colors.missed, label: widget.strings.legendMissed),
                _LegendChip(
                  color: scheme.outline,
                  label: widget.strings.legendUnrecorded,
                  outlined: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month - 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
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
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _MonthGrid(
              month: _month,
              today: _today,
              entries: _entries,
              onDayTap: _openDay,
              todayLabel: widget.strings.today,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
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
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
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
  });

  final DateTime month;
  final DateTime today;
  final Map<String, Entry> entries;
  final Future<void> Function(DateTime day) onDayTap;
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (first.weekday % 7); // Sunday-first
    final cells = <Widget>[
      for (final label in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
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
      padding: const EdgeInsets.all(12),
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
          color: bg ?? scheme.surface.withValues(alpha: isFuture ? 0.25 : 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? const Color(0xFFE67E22) : scheme.outline.withValues(alpha: 0.35),
            width: isToday ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: bg == null ? scheme.onSurface : Colors.white,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isToday)
              Text(
                todayLabel,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE67E22),
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.date, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(value: true, label: Text(widget.strings.takenLabel)),
              ButtonSegment(value: false, label: Text(widget.strings.missedLabel)),
            ],
            selected: {if (_taken != null) _taken!},
            onSelectionChanged: (value) => setState(() => _taken = value.isEmpty ? null : value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.strings.notes,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.strings.cancel),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _taken == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          _DayEditResult(taken: _taken!, notes: _notes.text.trim()),
                        ),
                child: Text(widget.strings.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
