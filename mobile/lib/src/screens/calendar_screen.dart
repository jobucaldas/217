import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'share_screens.dart';
import 'today_nudge.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.api,
    required this.user,
    required this.strings,
    required this.onOpenSettings,
    this.share = const ShareState(status: 'none'),
    this.onShareChanged,
    this.palette = AppPalette.azure,
  });

  final ApiClient api;
  final User user;
  final ShareState share;
  final Strings strings;
  final VoidCallback onOpenSettings;
  final ValueChanged<ShareState>? onShareChanged;
  final AppPalette palette;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  late DateTime _month;
  Map<String, Entry> _entries = {};
  Map<String, Entry> _prevEntries = {};
  Map<String, Entry> _nextEntries = {};
  Entry? _todayEntry;
  String? _error;

  /// Pixel drag offset: negative = finger left (peek next month).
  double _dragPx = 0;
  bool _monthDragging = false;
  late final AnimationController _monthSnap;
  Animation<double>? _monthSnapAnim;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String get _todayKey => DateFormat('yyyy-MM-dd').format(_today);

  DateTime get _prevMonth => DateTime(_month.year, _month.month - 1);
  DateTime get _nextMonth => DateTime(_month.year, _month.month + 1);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _monthSnap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_monthSnapAnim != null && mounted) {
          setState(() => _dragPx = _monthSnapAnim!.value);
        }
      });
    _load();
  }

  @override
  void dispose() {
    _monthSnap.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Silent reload: never insert a progress bar into the Column — that
    // reflows/shrinks the month carousel during swipe/chevron month changes.
    setState(() => _error = null);
    try {
      final year = _month.year;
      final month = _month.month;
      final results = await Future.wait([
        widget.api.listEntries(year, month),
        widget.api.listEntries(
          month == 1 ? year - 1 : year,
          month == 1 ? 12 : month - 1,
        ),
        widget.api.listEntries(
          month == 12 ? year + 1 : year,
          month == 12 ? 1 : month + 1,
        ),
      ]);
      if (!mounted) return;
      final map = {for (final e in results[0]) e.date: e};
      final prevMap = {for (final e in results[1]) e.date: e};
      final nextMap = {for (final e in results[2]) e.date: e};
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
        _prevEntries = prevMap;
        _nextEntries = nextMap;
        _todayEntry = todayEntry;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    }
  }

  void _shiftMonth(int delta) {
    if (delta == 0) return;
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) {
      setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _dragPx = 0;
      });
      _load();
      return;
    }
    // Chevron: animate slide with a light recoil, then commit.
    final target = delta > 0 ? -width : width;
    _animateMonthTo(target, commitDelta: delta);
  }

  void _onMonthDragStart(DragStartDetails _) {
    _monthSnap.stop();
    _monthSnapAnim = null;
    setState(() {
      _monthDragging = true;
      _dragPx = 0;
    });
  }

  void _onMonthDragUpdate(DragUpdateDetails details) {
    setState(() => _dragPx += details.delta.dx);
  }

  void _onMonthDragEnd(DragEndDetails details, double width) {
    final v = details.primaryVelocity ?? 0;
    final threshold = width * 0.22;
    int commit = 0;
    if (_dragPx <= -threshold || v < -480) {
      commit = 1; // next
    } else if (_dragPx >= threshold || v > 480) {
      commit = -1; // previous
    }
    final target = commit == 0 ? 0.0 : (commit > 0 ? -width : width);
    _animateMonthTo(target, commitDelta: commit);
  }

  void _animateMonthTo(double target, {required int commitDelta}) {
    final begin = _dragPx;
    // Slight overshoot on settle (recoil), not overblown.
    const recoil = Cubic(0.34, 1.22, 0.64, 1);
    final curve = commitDelta == 0 ? Curves.easeOutCubic : recoil;
    setState(() {
      _monthDragging = false;
      _monthSnapAnim = Tween<double>(begin: begin, end: target).animate(
        CurvedAnimation(parent: _monthSnap, curve: curve),
      );
    });
    _monthSnap.duration = Duration(
      milliseconds: commitDelta == 0 ? 220 : 300,
    );
    _monthSnap.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (commitDelta != 0) {
        setState(() {
          _month = DateTime(_month.year, _month.month + commitDelta);
          _dragPx = 0;
          _monthSnapAnim = null;
        });
        _load();
      } else {
        setState(() {
          _dragPx = 0;
          _monthSnapAnim = null;
        });
      }
    });
  }

  Future<void> _persistDay(String key, DayEditResult result) async {
    if (result.clear) {
      await widget.api.deleteEntry(key);
    } else {
      await widget.api.upsertEntry(
        key,
        taken: result.taken!,
        notes: result.notes,
        heart: result.heart,
      );
    }
    await _load();
  }

  Future<void> _openDay(DateTime day) async {
    if (!widget.share.canEditCalendar) {
      return;
    }
    final key = DateFormat('yyyy-MM-dd').format(day);
    final existing = key == _todayKey ? _todayEntry : _entries[key];
    // Persist via onCommit — not the sheet's pop value. Nested note-dialog
    // → sheet pop races on web and can drop the result (note/heart "save"
    // that only sticks after Taken/Missed re-tap).
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DayEditorSheet(
        strings: widget.strings,
        date: key,
        initialTaken: existing?.taken,
        initialNotes: existing?.notes ?? '',
        initialHeart: existing?.heart ?? false,
        hadEntry: existing != null,
        onCommit: (result) {
          _persistDay(key, result).catchError((Object err) {
            if (mounted) setState(() => _error = err.toString());
          });
        },
      ),
    );
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
    final nudgeVisible =
        TodayNudge.isVisible(_todayEntry) && widget.share.canEditCalendar;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.brand),
        actions: [
          if (widget.user.isOwner)
            IconButton(
              tooltip: widget.strings.inbox,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InboxScreen(
                      api: widget.api,
                      strings: widget.strings,
                    ),
                  ),
                );
              },
              icon: Badge(
                isLabelVisible: widget.share.unreadNotes > 0,
                label: Text('${widget.share.unreadNotes}'),
                child: const Icon(Icons.inbox_outlined),
              ),
            ),
          if (widget.user.isPartner && widget.share.isActive)
            IconButton(
              tooltip: widget.strings.leaveNote,
              onPressed: () => showPartnerNoteDialog(
                context: context,
                api: widget.api,
                strings: widget.strings,
              ),
              icon: const Icon(Icons.edit_note_outlined),
            ),
          IconButton(
            tooltip: widget.strings.settings,
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.share.canEditCalendar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    widget.strings.readOnlyCalendar,
                    style: text.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
                      onPressed: () => _shiftMonth(-1),
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
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              // Errors overlay the carousel instead of inserting Column chrome
              // that would shrink the month grid.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pageW = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _onMonthDragStart,
                      onHorizontalDragUpdate: _onMonthDragUpdate,
                      onHorizontalDragEnd: (d) => _onMonthDragEnd(d, pageW),
                      child: ClipRect(
                        key: const ValueKey('month-carousel'),
                        child: IgnorePointer(
                          ignoring: _monthDragging || _monthSnap.isAnimating,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.translate(
                                offset: Offset(_dragPx - pageW, 0),
                                child: _MonthGrid(
                                  key: ValueKey(
                                    '${_prevMonth.year}-${_prevMonth.month}',
                                  ),
                                  month: _prevMonth,
                                  today: _today,
                                  entries: _prevEntries,
                                  onDayTap: _openDay,
                                  todayLabel: widget.strings.today,
                                  portuguese: widget.strings.pt,
                                  palette: widget.palette,
                                  bottomInset: 12,
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(_dragPx, 0),
                                child: _MonthGrid(
                                  key: ValueKey(
                                    '${_month.year}-${_month.month}',
                                  ),
                                  month: _month,
                                  today: _today,
                                  entries: _entries,
                                  onDayTap: _openDay,
                                  todayLabel: widget.strings.today,
                                  portuguese: widget.strings.pt,
                                  palette: widget.palette,
                                  bottomInset: 12,
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(_dragPx + pageW, 0),
                                child: _MonthGrid(
                                  key: ValueKey(
                                    '${_nextMonth.year}-${_nextMonth.month}',
                                  ),
                                  month: _nextMonth,
                                  today: _today,
                                  entries: _nextEntries,
                                  onDayTap: _openDay,
                                  todayLabel: widget.strings.today,
                                  portuguese: widget.strings.pt,
                                  palette: widget.palette,
                                  bottomInset: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_error != null)
            Positioned(
              left: 20,
              right: 20,
              top: 8,
              child: Material(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ),
              ),
            ),
          if (nudgeVisible)
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
    super.key,
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
    final hasHeart = entry != null && entry!.heart;

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
                if (hasNote || hasHeart)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasHeart)
                        Icon(Icons.favorite, size: 11, color: onCell),
                      if (hasHeart && hasNote) const SizedBox(width: 2),
                      if (hasNote)
                        Icon(Icons.sticky_note_2_outlined,
                            size: 11, color: onCell),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DayEditResult {
  const DayEditResult.save({
    required this.taken,
    required this.notes,
    this.heart = false,
  }) : clear = false;
  const DayEditResult.clear()
      : clear = true,
        taken = null,
        notes = '',
        heart = false;

  final bool clear;
  final bool? taken;
  final String notes;
  final bool heart;
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
    this.initialHeart = false,
    this.onCommit,
  });

  final Strings strings;
  final String date;
  final bool? initialTaken;
  final String initialNotes;
  final bool initialHeart;
  final bool hadEntry;

  /// When set (production calendar), persist immediately — do not rely on the
  /// modal sheet's `Navigator.pop` value surviving a nested note dialog.
  final ValueChanged<DayEditResult>? onCommit;

  @override
  State<DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<DayEditorSheet> {
  late bool? _taken = widget.initialTaken;
  late String _notes = widget.initialNotes;
  late bool _heart = widget.initialHeart;

  DayEditResult _saveResult({
    required bool taken,
    required String notes,
    required bool heart,
  }) =>
      DayEditResult.save(taken: taken, notes: notes.trim(), heart: heart);

  void _emit(DayEditResult result) {
    final onCommit = widget.onCommit;
    if (onCommit != null) {
      onCommit(result);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
      return;
    }
    // Test harness / no callback: return result via sheet pop.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context, result);
    }
  }

  void _commitSave({String? notes, bool? heart}) {
    _emit(
      _saveResult(
        taken: _taken!,
        notes: notes ?? _notes,
        heart: heart ?? _heart,
      ),
    );
  }

  void _commitClear() {
    _emit(const DayEditResult.clear());
  }

  void _onStatusChanged(Set<bool> value) {
    if (value.isEmpty) {
      // Unselect — clear existing day mark (and note/heart) immediately.
      if (widget.hadEntry) {
        _commitClear();
      } else {
        setState(() => _taken = null);
      }
      return;
    }
    // Taken / Missed commits status + current note/heart and closes.
    _taken = value.first;
    _commitSave();
  }

  Future<void> _editNote() async {
    // Capture before the dialog await — sheet may unmount on web when the
    // nested route settles, and we still must persist note/heart.
    final onCommit = widget.onCommit;
    final result = await showDialog<_NoteDialogResult>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _NoteDialog(
        strings: widget.strings,
        initialNotes: _notes,
        initialHeart: _heart,
      ),
    );
    if (result == null) return;

    final notes = result.notes;
    final heart = result.heart;
    final status = _taken ?? widget.initialTaken;

    if (mounted) {
      setState(() {
        _notes = notes;
        _heart = heart;
        if (status != null) _taken = status;
      });
    }

    // Prefer live selection; fall back to the entry's existing status so Done
    // can persist note/heart without re-tapping Taken/Missed.
    if (status == null) {
      // Brand-new day with no status yet: keep note/heart until Taken/Missed.
      return;
    }

    final save = _saveResult(taken: status, notes: notes, heart: heart);
    if (onCommit != null) {
      // Persist first — independent of whether the sheet route still exists.
      onCommit(save);
    }
    // Close the sheet after the dialog route has fully popped (next frame),
    // so we do not race the root-navigator dialog dismissal on web.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (onCommit != null) {
        if (Navigator.of(context).canPop()) Navigator.pop(context);
      } else if (Navigator.of(context).canPop()) {
        Navigator.pop(context, save);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.pt ? 'pt_BR' : 'en_US';
    final human = DateFormat.yMMMMd(locale).format(DateTime.parse(widget.date));
    final scheme = Theme.of(context).colorScheme;
    final hasNote = _notes.trim().isNotEmpty;
    // Outside tap dismisses; no Cancel / Save — Done or Taken/Missed commit.
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
              if (_heart)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.favorite, color: scheme.primary, size: 20),
                ),
              IconButton.filledTonal(
                tooltip:
                    hasNote ? widget.strings.notes : widget.strings.addNote,
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
            onSelectionChanged: _onStatusChanged,
          ),
        ],
      ),
    );
  }
}

class _NoteDialogResult {
  const _NoteDialogResult({required this.notes, required this.heart});

  final String notes;
  final bool heart;
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.strings,
    required this.initialNotes,
    required this.initialHeart,
  });

  final Strings strings;
  final String initialNotes;
  final bool initialHeart;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNotes);
  late bool _heart = widget.initialHeart;

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
    final textTheme = Theme.of(context).textTheme;
    final hasText = _controller.text.trim().isNotEmpty;
    final onField = scheme.onSurface;
    final fieldFill = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.06),
      scheme.surface,
    );
    return AlertDialog(
      backgroundColor: scheme.surface,
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.strings.notes,
              style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
            ),
          ),
          IconButton(
            key: const ValueKey('note-heart-toggle'),
            tooltip:
                _heart ? widget.strings.heartMarked : widget.strings.heartMark,
            onPressed: () => setState(() => _heart = !_heart),
            icon: Icon(
              _heart ? Icons.favorite : Icons.favorite_border,
              color: _heart ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        cursorColor: scheme.primary,
        style: textTheme.bodyLarge?.copyWith(
          color: onField,
          fontSize: 17,
          height: 1.35,
        ),
        decoration: InputDecoration(
          hintText: widget.strings.addNote,
          hintStyle: textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
          filled: true,
          fillColor: fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 1.6),
          ),
        ),
      ),
      actions: [
        if (hasText)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _NoteDialogResult(notes: '', heart: _heart),
            ),
            child: Text(widget.strings.clearNote),
          ),
        // No Cancel — barrier / outside tap dismisses without saving.
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 44),
          ),
          onPressed: () => Navigator.pop(
            context,
            _NoteDialogResult(notes: _controller.text.trim(), heart: _heart),
          ),
          child: Text(widget.strings.done),
        ),
      ],
    );
  }
}
