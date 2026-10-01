import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'today_nudge.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.api,
    required this.user,
    required this.strings,
    required this.onLogout,
    required this.onOpenSettings,
    this.palette = AppPalette.azure,
  });

  final ApiClient api;
  final User user;
  final Strings strings;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenSettings;
  final AppPalette palette;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  Map<String, Entry> _entries = {};
  Entry? _todayEntry;
  bool _loading = true;
  String? _error;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String get _todayKey => DateFormat('yyyy-MM-dd').format(_today);

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
      final map = {for (final e in entries) e.date: e};
      Entry? todayEntry;
      final today = _today;
      if (_month.year == today.year && _month.month == today.month) {
        todayEntry = map[_todayKey];
      } else {
        try {
          final list = await widget.api.listEntries(today.year, today.month);
          for (final e in list) {
            if (e.date == _todayKey) {
              todayEntry = e;
              break;
            }
          }
        } catch (_) {
          todayEntry = _todayEntry;
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = map;
        _todayEntry = todayEntry;
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
    final existing = key == _todayKey ? _todayEntry : _entries[key];
    final result = await showModalBottomSheet<DayEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DayEditorSheet(
        strings: widget.strings,
        date: key,
        initialTaken: existing?.taken,
        initialNotes: existing?.notes ?? '',
        hadEntry: existing != null,
      ),
    );
    if (result == null) return;
    if (result.clear) {
      await widget.api.deleteEntry(key);
    } else {
      await widget.api.upsertEntry(
        key,
        taken: result.taken!,
        notes: result.notes,
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.pt ? 'pt_BR' : 'en_US';
    final monthLabel = DateFormat.yMMMM(locale).format(_month);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final todayStatus = _todayEntry == null
        ? widget.strings.unrecorded
        : (_todayEntry!.taken ? widget.strings.taken : widget.strings.missed);
    final todayColor = _todayEntry == null
        ? scheme.onSurfaceVariant
        : (_todayEntry!.taken
            ? App217Colors.statusTaken(brightness, widget.palette)
            : App217Colors.statusMissed(brightness, widget.palette));
    final humanDate = DateFormat.MMMMd(locale).format(_today);
    final nudgeVisible = TodayNudge.isVisible(_todayEntry);

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
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    _LegendDot(
                      color: App217Colors.statusTaken(brightness, widget.palette),
                      label: widget.strings.legendTaken,
                    ),
                    const SizedBox(width: 14),
                    _LegendDot(
                      color:
                          App217Colors.statusMissed(brightness, widget.palette),
                      label: widget.strings.legendMissed,
                    ),
                    const SizedBox(width: 14),
                    _LegendDot(
                      color: scheme.onSurfaceVariant,
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
                        setState(
                          () =>
                              _month = DateTime(_month.year, _month.month - 1),
                        );
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
                        setState(
                          () =>
                              _month = DateTime(_month.year, _month.month + 1),
                        );
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  palette: widget.palette,
                  bottomInset: nudgeVisible ? 72 : 12,
                ),
              ),
            ],
          ),
          TodayNudge(
            strings: widget.strings,
            todayEntry: _todayEntry,
            onRecord: () => _openDay(_today),
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
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
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
    required this.palette,
    required this.bottomInset,
  });

  final DateTime month;
  final DateTime today;
  final Map<String, Entry> entries;
  final Future<void> Function(DateTime day) onDayTap;
  final String todayLabel;
  final bool portuguese;
  final AppPalette palette;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sunday-first
    final weekdayLabels = portuguese
        ? const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
        : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final rowCount = ((leading + daysInMonth) / 7).ceil();

    Widget slot(int index) {
      if (index < leading || index >= leading + daysInMonth) {
        return const SizedBox.expand();
      }
      final day = index - leading + 1;
      final date = DateTime(month.year, month.month, day);
      return _DayCell(
        day: date,
        today: today,
        todayLabel: todayLabel,
        entry: entries[DateFormat('yyyy-MM-dd').format(date)],
        onTap: onDayTap,
        palette: palette,
      );
    }

    // Exact-fit rows: each week gets 1/rowCount of remaining height so the
    // full month never crops on short or ultrawide viewports (GridView
    // aspect-ratio clamps used to overflow).
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, bottomInset),
      child: Column(
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                for (final label in weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (var row = 0; row < rowCount; row++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: slot(row * 7 + col),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
    required this.palette,
  });

  final DateTime day;
  final DateTime today;
  final String todayLabel;
  final Entry? entry;
  final Future<void> Function(DateTime day) onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    Color? bg;
    if (entry != null) {
      bg = entry!.taken
          ? App217Colors.cellTaken(brightness, palette)
          : App217Colors.cellMissed(brightness, palette);
    }
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final isFuture = day.isAfter(today);
    final emptyBg = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: isFuture ? 0.05 : 0.08),
      scheme.surface,
    );
    final onCell = bg == null
        ? scheme.onSurface
        : App217Colors.onFilledCell(brightness, palette);
    final hasNote = entry != null && entry!.notes.trim().isNotEmpty;

    return InkWell(
      onTap: isFuture ? null : () => onTap(day),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg ?? emptyBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isToday ? scheme.primary : scheme.outline.withValues(alpha: 0.55),
            width: isToday ? 2.2 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: onCell,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (isToday)
                  Text(
                    todayLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: bg == null ? scheme.primary : onCell,
                    ),
                  ),
                if (hasNote)
                  Icon(Icons.sticky_note_2_outlined, size: 11, color: onCell),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DayEditResult {
  const DayEditResult.save({required this.taken, required this.notes})
      : clear = false;
  const DayEditResult.clear()
      : clear = true,
        taken = null,
        notes = '';

  final bool clear;
  final bool? taken;
  final String notes;
}

/// Day mark bottom sheet: status + note affordance aligned with the date.
class DayEditorSheet extends StatefulWidget {
  const DayEditorSheet({
    super.key,
    required this.strings,
    required this.date,
    required this.initialTaken,
    required this.initialNotes,
    required this.hadEntry,
  });

  final Strings strings;
  final String date;
  final bool? initialTaken;
  final String initialNotes;
  final bool hadEntry;

  @override
  State<DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<DayEditorSheet> {
  late bool? _taken = widget.initialTaken;
  late String _notes = widget.initialNotes;

  /// Save when a status is chosen, or when clearing an existing mark.
  bool get _canSave => _taken != null || widget.hadEntry;

  Future<void> _editNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(
        strings: widget.strings,
        initialNotes: _notes,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _notes = result);
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.pt ? 'pt_BR' : 'en_US';
    final human = DateFormat.yMMMMd(locale).format(DateTime.parse(widget.date));
    final scheme = Theme.of(context).colorScheme;
    final hasNote = _notes.trim().isNotEmpty;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  human,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: hasNote ? widget.strings.notes : widget.strings.addNote,
                onPressed: _editNote,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      hasNote
                          ? Icons.sticky_note_2
                          : Icons.sticky_note_2_outlined,
                    ),
                    if (!hasNote)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Icon(
                          Icons.add_circle,
                          size: 14,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.strings.pickStatus,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(
                value: true,
                label: Text(widget.strings.takenLabel),
              ),
              ButtonSegment(
                value: false,
                label: Text(widget.strings.missedLabel),
              ),
            ],
            selected: {if (_taken != null) _taken!},
            onSelectionChanged: (value) =>
                setState(() => _taken = value.isEmpty ? null : value.first),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !_canSave
                ? null
                : () {
                    if (_taken == null) {
                      Navigator.pop(context, const DayEditResult.clear());
                    } else {
                      Navigator.pop(
                        context,
                        DayEditResult.save(
                          taken: _taken!,
                          notes: _notes.trim(),
                        ),
                      );
                    }
                  },
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

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.strings,
    required this.initialNotes,
  });

  final Strings strings;
  final String initialNotes;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNotes);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.strings.notes),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurface,
            ),
        decoration: InputDecoration(
          hintText: widget.strings.addNote,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        if (hasText)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(widget.strings.clearNote),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 44),
          ),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.strings.done),
        ),
      ],
    );
  }
}
