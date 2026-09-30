import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';

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
      if (!mounted) return;
      setState(() {
        _entries = {for (final e in entries) e.date: e};
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
        initialTaken: existing?.taken ?? true,
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
                  child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
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
          Expanded(child: _MonthGrid(month: _month, entries: _entries, onDayTap: _openDay)),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.entries,
    required this.onDayTap,
  });

  final DateTime month;
  final Map<String, Entry> entries;
  final Future<void> Function(DateTime day) onDayTap;

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
  const _DayCell({required this.day, required this.entry, required this.onTap});

  final DateTime day;
  final Entry? entry;
  final Future<void> Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? bg;
    if (entry != null) {
      bg = entry!.taken ? const Color(0xFF1F6F5B) : scheme.error;
    }
    final today = DateTime.now();
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    return InkWell(
      onTap: () => onTap(day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: bg == null ? null : Colors.white,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
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
  final bool initialTaken;
  final String initialNotes;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late bool _taken = widget.initialTaken;
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
            segments: [
              ButtonSegment(value: true, label: Text(widget.strings.taken)),
              ButtonSegment(value: false, label: Text(widget.strings.missed)),
            ],
            selected: {_taken},
            onSelectionChanged: (value) => setState(() => _taken = value.first),
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
                onPressed: () => Navigator.pop(
                  context,
                  _DayEditResult(taken: _taken, notes: _notes.text.trim()),
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
