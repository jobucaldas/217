import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// The small symbol a calendar mark has in the legend and the day tags:
/// a dot (Taken/Missed, outlined when open), an icon, or the dashed PMS ring.
class DayMark extends StatelessWidget {
  const DayMark({
    super.key,
    required this.color,
    this.outlined = false,
    this.dashed = false,
    this.icon,
  });

  final Color color;
  final bool outlined;

  /// Dashed rounded square, as drawn around expected PMS days.
  final bool dashed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon != null) return Icon(icon, size: 14, color: color);
    if (dashed) {
      return CustomPaint(
        size: const Size(14, 14),
        painter: DashedRingPainter(
          color: color,
          radius: 4,
          strokeWidth: 1.4,
          dash: 2.5,
          gap: 2.5,
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}

/// Bottom of the calendar: tags for what the selected day holds and, for
/// whoever can edit, the button that opens that day's editor.
class DaySummaryBar extends StatelessWidget {
  const DaySummaryBar({
    super.key,
    required this.strings,
    required this.day,
    required this.isToday,
    required this.entry,
    required this.cycleKind,
    required this.palette,
    this.onEdit,
    this.onView,
    this.onJumpToToday,
    this.isFuture = false,
    this.note = '',
    this.noteAsTag = false,
    this.onOpenNote,
  });

  final Strings strings;
  final DateTime day;
  final bool isToday;
  final Entry? entry;
  final CycleDayKind cycleKind;
  final AppPalette palette;

  /// Null on read-only calendars: they get [onView] instead.
  final VoidCallback? onEdit;

  /// Read-only calendars: opens the day sheet read-only.
  final VoidCallback? onView;

  /// Set when the selected day or visible month is not today's.
  final VoidCallback? onJumpToToday;

  /// Future days show only what is expected: nothing can be logged ahead of
  /// time, so the button views the day (read-only) instead of updating it.
  final bool isFuture;

  /// The day's note, drawn above the tags so it keeps one fixed place at the
  /// bottom of the screen whatever the month shows.
  final String note;

  /// Short screens: the note is not drawn; its tag opens it in a card.
  final bool noteAsTag;

  /// Opens the note card (see [showDayNoteCard]) from the note tag.
  final VoidCallback? onOpenNote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final shortDay = strings.dates.shortDayMonth(day);
    final taken = entry?.taken;
    final period = App217Colors.period(brightness, palette);
    final loggedPeriod = entry?.period ?? false;

    final tags = <Widget>[
      if (taken == null && !isFuture)
        _DayTag(
          key: const ValueKey('day-tag-status'),
          label: strings.unrecorded,
          color: scheme.onSurfaceVariant,
          mark: DayMark(color: scheme.onSurfaceVariant, outlined: true),
        )
      else if (taken != null)
        _DayTag(
          key: const ValueKey('day-tag-status'),
          label: taken ? strings.taken : strings.missed,
          color: taken
              ? App217Colors.statusTaken(brightness, palette)
              : App217Colors.statusMissed(brightness, palette),
          mark: DayMark(
            color: taken
                ? App217Colors.statusTaken(brightness, palette)
                : App217Colors.statusMissed(brightness, palette),
          ),
        ),
      if (loggedPeriod)
        _DayTag(
          key: const ValueKey('day-tag-period'),
          label: strings.periodLabel,
          color: period,
          mark: DayMark(color: period, icon: Icons.water_drop),
        )
      else if (cycleKind == CycleDayKind.expectedPeriod)
        _DayTag(
          key: const ValueKey('day-tag-expected-period'),
          label: strings.expectedPeriod,
          color: period,
          mark: DayMark(color: period, icon: Icons.water_drop_outlined),
        ),
      if (cycleKind == CycleDayKind.pms)
        _DayTag(
          key: const ValueKey('day-tag-pms'),
          label: strings.expectedPms,
          color: App217Colors.pms(brightness, palette),
          mark: DayMark(
            color: App217Colors.pms(brightness, palette),
            dashed: true,
          ),
        ),
      if (entry?.heart ?? false)
        _DayTag(
          key: const ValueKey('day-tag-heart'),
          label: strings.heartLabel,
          color: App217Colors.intimacy(brightness, palette),
          mark: DayMark(
            color: App217Colors.intimacy(brightness, palette),
            icon: Icons.favorite,
          ),
        ),
      // The inline note panel already shows it; the tag only stands in for it.
      if (noteAsTag && entry != null && entry!.notes.trim().isNotEmpty)
        _DayTag(
          key: const ValueKey('day-tag-note'),
          label: strings.notes,
          onPressed: onOpenNote,
          color: scheme.primary,
          mark: DayMark(
            color: scheme.primary,
            icon: Icons.sticky_note_2_outlined,
          ),
        ),
    ];

    // Keyed by day: tags open on one day start closed on the next.
    final tagWrap = Wrap(
      key: ValueKey(day),
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            isToday ? strings.today : shortDay,
            style: text.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ...tags,
      ],
    );
    // Wide windows, and short ones with room across (landscape), put the
    // button beside the tags so the month grid keeps its height. Narrow
    // windows stack them: beside a button the tags would not fit.
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width >= 600 || (size.height < 600 && size.width >= 480);
    // Future days are only viewed, even on an editable calendar: their sheet
    // is read-only and shows what is expected.
    final viewing =
        (onEdit == null && onView != null) || (isFuture && onEdit != null);
    // Web and desktop default to a compact density that would shrink the
    // pill below the square button beside it; both are pinned to one height.
    final barHeight = compact ? 48.0 : 52.0;
    final button = onEdit == null && onView == null
        ? null
        : SizedBox(
            height: barHeight,
            child: FilledButton.icon(
              key: ValueKey(viewing ? 'view-day-button' : 'update-day-button'),
              onPressed: onView ?? onEdit,
              // The theme's full-width minimum would not fit beside the tags.
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: compact ? Size(0, barHeight) : null,
              ),
              icon: Icon(viewing
                  ? Icons.visibility_outlined
                  : Icons.edit_calendar_outlined),
              label: Text(viewing
                  ? (isToday ? strings.viewToday : strings.viewDay(shortDay))
                  : (isToday
                      ? strings.updateToday
                      : strings.updateDay(shortDay))),
            ),
          );

    // Shown only away from today, at the action button's height, so the bar
    // keeps its height and the calendar above never moves.
    final jump = onJumpToToday == null
        ? null
        : SizedBox.square(
            dimension: barHeight,
            child: IconButton.filledTonal(
              key: const ValueKey('jump-to-today-button'),
              // Square, with the corners of the update-day button beside it.
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              tooltip: strings.jumpToToday,
              onPressed: onJumpToToday,
              icon: const Icon(Icons.today),
            ),
          );
    final actions = button == null
        ? null
        : Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (compact) button else Expanded(child: button),
              if (jump != null) ...[const SizedBox(width: 8), jump],
            ],
          );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, compact ? 8 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note.isNotEmpty && !noteAsTag) ...[
              // Capped to three lines; tapping opens the whole note.
              DayNotePanel(
                notes: note,
                maxLines: 3,
                onTap: onOpenNote,
                semanticsLabel: strings.notes,
              ),
              const SizedBox(height: 8),
            ],
            _summary(compact, tagWrap, actions),
          ],
        ),
      ),
    );
  }

  Widget _summary(bool compact, Widget tagWrap, Widget? button) {
    return compact
        ? Row(
            key: const ValueKey('day-summary'),
            children: [
              Expanded(child: tagWrap),
              if (button != null) ...[
                const SizedBox(width: 12),
                button,
              ],
            ],
          )
        : Column(
            key: const ValueKey('day-summary'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tagWrap,
              if (button != null) ...[
                const SizedBox(height: 10),
                button,
              ],
            ],
          );
  }
}

/// Rounded tag tinted with the mark's colour, showing only the mark until
/// tapped; the label then stays on-surface ink so it reads in both themes.
class _DayTag extends StatefulWidget {
  const _DayTag({
    super.key,
    required this.label,
    required this.color,
    required this.mark,
    this.onPressed,
  });

  final String label;
  final Color color;
  final Widget mark;

  /// Replaces the open/close toggle, e.g. to show something larger.
  final VoidCallback? onPressed;

  @override
  State<_DayTag> createState() => _DayTagState();
}

class _DayTagState extends State<_DayTag> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color;
    void toggle() {
      final onPressed = widget.onPressed;
      if (onPressed != null) {
        onPressed();
      } else {
        setState(() => _open = !_open);
      }
    }

    return Semantics(
      button: true,
      label: widget.label,
      expanded: widget.onPressed == null ? _open : null,
      excludeSemantics: true,
      onTap: toggle,
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.14), scheme.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: toggle,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              // At least a 32px touch target while closed.
              constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _open ? 10 : 0,
                  vertical: 5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.mark,
                    if (_open) ...[
                      const SizedBox(width: 6),
                      // Never wider than the space the tag row gives it.
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected day's note, shown above the day tags. Display only: swipes pass through to the month carousel.
class DayNotePanel extends StatelessWidget {
  const DayNotePanel({
    super.key,
    required this.notes,
    this.alignment = Alignment.topCenter,
    this.maxLines,
    this.onTap,
    this.semanticsLabel,
  });

  final String notes;

  /// Announced before the note (e.g. "Note"); the panel reads as a button
  /// when it opens the note.
  final String? semanticsLabel;

  /// Opens the full note; without it the panel ignores taps.
  final VoidCallback? onTap;

  /// Fixed line cap; when null the panel fits the room it is given.
  final int? maxLines;

  /// Where the panel sits in the room it is given.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = text.bodyLarge?.copyWith(color: scheme.onSurface);
    return IgnorePointer(
      ignoring: onTap == null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same text scaling the Text below gets from the device setting.
          final lineHeight =
              MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 17) *
                  (style?.height ?? 1.4);
          // 24px of vertical padding inside the panel.
          final lines = maxLines ??
              ((constraints.maxHeight - 24) / lineHeight).floor().clamp(1, 12);
          final panel = Container(
            key: const ValueKey('day-note'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            // Tinted with the accent, like the note tag it stands for.
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.14),
                scheme.surface,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.sticky_note_2_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notes,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          );
          final label =
              semanticsLabel == null ? notes : '$semanticsLabel: $notes';
          return Align(
            alignment: alignment,
            child: Semantics(
              button: onTap != null,
              label: label,
              excludeSemantics: true,
              onTap: onTap,
              child: onTap == null
                  ? panel
                  : Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: onTap,
                        child: panel,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Dashed rounded-rect outline hugging the widget's bounds.
class DashedRingPainter extends CustomPainter {
  const DashedRingPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRingPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}

/// Read-only note card, styled like the note dialog of the day editor.
/// Follows [notes] live and closes itself once it is empty, so a card never
/// outlives the data it shows (e.g. calendar access cleared).
Future<void> showDayNoteCard(
  BuildContext context, {
  required String title,
  required ValueListenable<String> notes,
}) {
  // One close per card, however often the empty note rebuilds.
  var closing = false;
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      final textTheme = Theme.of(dialogContext).textTheme;
      final fieldFill = Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.06),
        scheme.surface,
      );
      return ValueListenableBuilder<String>(
        valueListenable: notes,
        builder: (_, value, __) {
          if (value.isEmpty) {
            if (!closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) closeOwnRoute(dialogContext);
              });
            }
            return const SizedBox.shrink();
          }
          return AlertDialog(
            key: const ValueKey('day-note-card'),
            backgroundColor: scheme.surface,
            title: Text(
              title,
              style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
            ),
            content: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline),
                ),
                child: Text(
                  value,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface,
                    fontSize: 17,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// What the owner's day editor hands the [ExpandableDaySheet]: the day as
/// edited so far, the ways to change it, and the editor's own controls.
class DayEditing {
  const DayEditing({
    required this.notes,
    required this.heart,
    required this.period,
    required this.onToggleHeart,
    required this.onTogglePeriod,
    required this.onEditNote,
    required this.onSaveNote,
    required this.actions,
    required this.status,
  });

  final String notes;
  final bool heart;
  final bool period;
  final VoidCallback onToggleHeart;
  final VoidCallback onTogglePeriod;
  final VoidCallback onEditNote;

  /// Saves the note written inline on the open sheet's note card.
  final ValueChanged<String> onSaveNote;

  /// The sex, period and note buttons shown beside the date at rest.
  final Widget actions;

  /// The Missed/Taken control, pinned to the bottom of the sheet.
  final Widget status;
}

/// What an open day sheet shows besides the editor's own state: the logged
/// entry, the predictions and today's date. The calendar feeds it a new one
/// whenever any of them changes, so an open sheet never goes stale.
class DayView {
  const DayView(
      {required this.entry, required this.cycle, required this.today});

  final Entry? entry;
  final CycleInfo cycle;
  final DateTime today;

  bool sameAs(DayView other) =>
      identical(entry, other.entry) &&
      identical(cycle, other.cycle) &&
      today == other.today;
}

/// A day sheet that can be pulled up, for both sides of a calendar.
///
/// Editable (the owner's past days and today, [editor] set): at rest the
/// date with the sex, period and note buttons; pulled up those buttons
/// become cards (still tappable) and the Missed/Taken control stays pinned
/// to the bottom. Read-only (a partner, or the owner's future days): chips
/// at rest that turn into cards when pulled up, with a lock beside the date
/// on the owner's future days. Either way it also shows what is coming up
/// once pulled up.
///
/// Dragging anywhere on it (or tapping its handle) opens and closes it. A
/// pull down from open stops at the resting size; only a pull from rest
/// dismisses it. A tap outside closes it from either size.
class ExpandableDaySheet extends StatefulWidget {
  const ExpandableDaySheet({
    super.key,
    required this.strings,
    required this.palette,
    required this.day,
    required this.view,
    this.editor,
    this.partner = false,
  });

  final Strings strings;
  final AppPalette palette;
  final DateTime day;

  /// The day's entry, the predictions and today, followed live. The
  /// [editor]'s note, when set, wins over the entry's.
  final ValueListenable<DayView> view;

  /// The owner's editor; null when the day is read-only.
  final DayEditing? editor;

  /// Read by a partner rather than the owner (lock on future days).
  final bool partner;

  @override
  State<ExpandableDaySheet> createState() => _ExpandableDaySheetState();
}

class _ExpandableDaySheetState extends State<ExpandableDaySheet> {
  final _controller = DraggableScrollableController();

  /// 0 at rest, 1 fully open: drives the cross-fade between the two looks.
  final _progress = ValueNotifier<double>(0);
  final _headKey = GlobalKey();
  final _chipsKey = GlobalKey();
  final _barKey = GlobalKey();
  final _contentKey = GlobalKey();

  /// Measured heights: handle and date, the resting extras (chips and the
  /// pull-up hint), the pinned
  /// Missed/Taken bar and the whole scrolling content.
  double? _headPx;
  double? _chipsPx;
  double? _barPx;
  double? _contentPx;

  /// What the last measurement was scheduled for: width, text scale and
  /// everything that changes the content. Measuring again waits for a change.
  Object? _measureSig;
  bool _measureQueued = false;

  /// Sheet sizes, as fractions of the room the modal gives it.
  double _resting = 0.25;
  double _max = 0.7;
  double _height = 1;

  /// Kept as one list while [_resting] holds: a new list makes the sheet
  /// snap, which would cut a drag short.
  List<double> _snapSizes = const [0.25];

  /// Whether the pointer that is down came while the sheet was open: that
  /// pull ends at rest, it cannot dismiss the sheet.
  bool _fromOpen = false;
  ScrollController? _scroll;

  bool get _editable => widget.editor != null;

  @override
  void dispose() {
    _controller.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// Measures once after the frame when [sig] is not what was last measured.
  void _measureIfChanged(Object sig) {
    if (sig == _measureSig || _measureQueued) return;
    _measureSig = sig;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      _measure();
    });
  }

  /// Fits the resting and open sizes to what was laid out.
  void _measure() {
    if (!mounted) return;
    double? height(GlobalKey key) => key.currentContext?.size?.height;
    final head = height(_headKey);
    final content = height(_contentKey);
    final chips = height(_chipsKey);
    final bar = _editable ? height(_barKey) : 0.0;
    if (head == null || content == null || chips == null || bar == null) {
      return;
    }
    bool differs(double? a, double b) => a == null || (a - b).abs() > 0.5;
    if (differs(_headPx, head) ||
        differs(_chipsPx, chips) ||
        differs(_barPx, bar) ||
        differs(_contentPx, content)) {
      setState(() {
        _headPx = head;
        _chipsPx = chips;
        _barPx = bar;
        _contentPx = content;
      });
    }
  }

  bool get _openNow => _controller.size > _resting + 0.002;

  void _toggle() {
    if (!_controller.isAttached || _max <= _resting) return;
    final open = _controller.size > (_resting + _max) / 2;
    // Back at rest the date leads again, not wherever the cards were.
    final scroll = _scroll;
    if (open && scroll != null && scroll.hasClients && scroll.offset > 0) {
      scroll.jumpTo(0);
    }
    _controller.animateTo(
      open ? _resting : _max,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onExtent(DraggableScrollableNotification n) {
    if (_fromOpen && n.extent < _resting - 0.0001 && _controller.isAttached) {
      // A pull from open stops at rest; the rest of that pull is dropped.
      // Not passed on: at 0 the modal would close.
      _controller.jumpTo(_resting);
      return true;
    }
    final span = _max - _resting;
    _progress.value =
        span <= 0 ? 0 : ((n.extent - _resting) / span).clamp(0.0, 1.0);
    return false;
  }

  /// Drags on the pinned Missed/Taken bar move the sheet like its body does.
  void _barDragStart(DragStartDetails _) {
    _fromOpen = _controller.isAttached && _openNow;
  }

  void _barDragUpdate(DragUpdateDetails d) {
    if (!_controller.isAttached || _height <= 0) return;
    final min = _fromOpen ? _resting : 0.0;
    _controller.jumpTo(
      (_controller.size - (d.primaryDelta ?? 0) / _height).clamp(min, _max),
    );
  }

  void _barDragEnd(DragEndDetails d) {
    if (!_controller.isAttached) return;
    final size = _controller.size;
    final v = d.primaryVelocity ?? 0;
    final stops = [if (!_fromOpen) 0.0, _resting, _max];
    final double target;
    if (v.abs() > 500) {
      // A flick goes one stop its way (positive is down).
      target = v > 0
          ? stops.lastWhere((s) => s < size - 0.002, orElse: () => stops.first)
          : stops.firstWhere((s) => s > size + 0.002, orElse: () => _max);
    } else {
      target =
          stops.reduce((a, b) => (a - size).abs() <= (b - size).abs() ? a : b);
    }
    if ((target - size).abs() < 0.001) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DayView>(
      valueListenable: widget.view,
      builder: (context, view, _) => _build(
        context,
        view,
        widget.editor?.notes.trim() ?? view.entry?.notes.trim() ?? '',
      ),
    );
  }

  /// [child] at [opacity], out of reach (taps and screen readers) once it
  /// has faded below half.
  static Widget _fade(double opacity, Widget child) => IgnorePointer(
        ignoring: opacity < 0.5,
        child: ExcludeSemantics(
          excluding: opacity < 0.5,
          child: Opacity(opacity: opacity, child: child),
        ),
      );

  /// [t] mapped onto [begin]..[end], eased.
  static double _span(double t, double begin, double end) =>
      Curves.easeInOut.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  Widget _build(BuildContext context, DayView view, String note) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strings = widget.strings;
    final editor = widget.editor;
    final padding = MediaQuery.paddingOf(context);

    final handle = ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, t, _) => Semantics(
        button: true,
        label: t > 0.5 ? strings.daySheetLess : strings.daySheetMore,
        excludeSemantics: true,
        onTap: _toggle,
        child: GestureDetector(
          key: const ValueKey('day-sheet-handle'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SizedBox(
            height: 28,
            child: Align(
              alignment: const Alignment(0, -0.1),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Widget? trailing;
    if (editor != null) {
      // The buttons give way to their cards as the sheet opens.
      // Its room goes with it, so the open date gets the whole width.
      trailing = ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, t, child) {
          final shown = 1 - _span(t, 0, 0.45);
          return Align(
            alignment: AlignmentDirectional.centerEnd,
            widthFactor: 1 - _span(t, 0, 0.5),
            child: _fade(shown, child!),
          );
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: editor.actions,
        ),
      );
    } else {
      // A partner reads every day: the "Partner Mode" mark on the calendar
      // already says so.
      trailing = widget.partner
          ? null
          : _SheetBadge(
              key: const ValueKey('day-sheet-locked'),
              icon: Icons.lock_outline,
              label: strings.daySheetFutureLocked,
            );
    }
    final dateRow = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.dates.fullDate(widget.day),
              style: theme.textTheme.headlineMedium,
            ),
          ),
          if (trailing != null) ...[
            if (editor == null) const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
    final head = Column(
      key: _headKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        handle,
        if (editor != null)
          dateRow
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: dateRow,
          ),
      ],
    );

    final more = Padding(
      key: const ValueKey('day-more'),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + (editor == null ? padding.bottom : 0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: editor != null
            ? _ownerCards(context, view, note, editor)
            : _readOnlyCards(context, view, note),
      ),
    );
    // What shows at rest and fades away as the sheet opens: the chips of a
    // read-only day, then a "more" mark saying the sheet can be pulled up.
    final hint = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(
        height: 24,
        child: Center(
          child: Icon(
            Icons.more_horiz,
            size: 24,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
    final Widget rest;
    if (editor != null) {
      rest = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        // The owner's editable day needs no "more" mark: only a little
        // room above the pinned Missed/Taken.
        child: KeyedSubtree(key: _chipsKey, child: const SizedBox(height: 4)),
      );
    } else {
      rest = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Padding(
          key: _chipsKey,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DayChips(
                key: ValueKey(
                    widget.partner ? 'partner-day-glance' : 'owner-day-glance'),
                strings: strings,
                palette: widget.palette,
                entry: view.entry,
                note: note,
                cycleKind: view.cycle.kindOf(widget.day),
                cycleDetail: _cycleDetail(context, view),
                isFuture: isFutureDay(widget.day, view.today),
              ),
              hint,
            ],
          ),
        ),
      );
    }
    // The rest block sits where the cards will be, and fades into them.
    final body = ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, t, _) {
        final cards =
            _span(t, editor != null ? 0.1 : 0.35, editor != null ? 0.6 : 0.85);
        final restOpacity = 1 - _span(t, 0, editor != null ? 0.3 : 0.4);
        return Stack(
          children: [
            // Fully transparent paints nothing, but still gives the height.
            _fade(cards, more),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _fade(restOpacity, rest),
            ),
          ],
        );
      },
    );
    final content = Column(
      key: _contentKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [head, body],
    );

    final bar = editor == null
        ? null
        : GestureDetector(
            onVerticalDragStart: _barDragStart,
            onVerticalDragUpdate: _barDragUpdate,
            onVerticalDragEnd: _barDragEnd,
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, t, child) => DecoratedBox(
                key: _barKey,
                // A hairline once cards scroll under it.
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: t),
                    ),
                  ),
                ),
                child: child,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + padding.bottom),
                // Full width, as in the plain editor's stretched column.
                child: SizedBox(width: double.infinity, child: editor.status),
              ),
            ),
          );

    // The note is written right in the sheet: it sits above the keyboard.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _sized(context, padding, editor, content, bar, view, note),
    );
  }

  Widget _sized(BuildContext context, EdgeInsets padding, DayEditing? editor,
      Widget content, Widget? bar, DayView view, String note) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        _height = height;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        _measureIfChanged((
          constraints.maxWidth,
          scale,
          note,
          view,
          editor?.heart,
          editor?.period,
        ));
        // First frame: estimates until the parts are measured. At rest the
        // date and the chips (or the pinned bar), clear of the system
        // navigation bar; open, everything.
        final headPx = _headPx;
        final restingPx = headPx == null
            ? 170 * scale + padding.bottom
            : headPx + _chipsPx! + (editor != null ? _barPx! : padding.bottom);
        final contentPx = _contentPx == null
            ? height
            : _contentPx! + (editor != null ? _barPx! : 0);
        final top = ((height - padding.top - 24) / height).clamp(0.3, 1.0);
        _resting = (restingPx / height).clamp(0.1, top);
        _max = (contentPx / height).clamp(_resting, top);
        if (_snapSizes.single != _resting) _snapSizes = [_resting];
        final restingHeight = _resting * height;
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: _onExtent,
          child: Listener(
            onPointerDown: (_) =>
                _fromOpen = _controller.isAttached && _openNow,
            child: DraggableScrollableSheet(
              controller: _controller,
              expand: false,
              snap: true,
              initialChildSize: _resting,
              // Below the resting size is only the way out: the modal closes
              // once the sheet reaches 0.
              minChildSize: 0,
              maxChildSize: _max,
              snapSizes: _snapSizes,
              builder: (context, controller) {
                _scroll = controller;
                return Material(
                  color: scheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // Below its resting size the sheet slides away whole
                      // rather than squeezing the pinned bar.
                      final h = math.max(box.maxHeight, restingHeight);
                      return OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: h,
                        maxHeight: h,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                key: const ValueKey('expandable-day-sheet'),
                                controller: controller,
                                // Content shorter than the sheet still has
                                // to take the drag, or the sheet could
                                // never be pulled up.
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: content,
                              ),
                            ),
                            if (bar != null) bar,
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The owner's open sheet: sex and period as tiles that still edit the
  /// day (plus the day's prediction), the note as a card, then what is
  /// coming up.
  List<Widget> _ownerCards(
      BuildContext context, DayView view, String note, DayEditing e) {
    final strings = widget.strings;
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final cycleKind = view.cycle.kindOf(widget.day);
    return [
      _TileGrid(
        children: [
          _InfoTile(
            key: const ValueKey('day-card-heart'),
            color: App217Colors.intimacy(brightness, widget.palette),
            icon: e.heart ? Icons.favorite : Icons.favorite_border,
            title: strings.heartLabel,
            value: e.heart ? strings.dayLogged : strings.dayTapToLog,
            muted: !e.heart,
            selected: e.heart,
            onTap: e.onToggleHeart,
          ),
          _InfoTile(
            key: const ValueKey('day-card-period'),
            color: App217Colors.period(brightness, widget.palette),
            icon: e.period ? Icons.water_drop : Icons.water_drop_outlined,
            title: strings.periodLabel,
            value: e.period
                ? strings.dayLogged
                : (cycleKind == CycleDayKind.expectedPeriod
                    ? (_viewingToday(view)
                        ? '${strings.dayExpected} ${_until(context, view)}'
                        : strings.dayExpected)
                    : strings.dayTapToLog),
            muted: !e.period && cycleKind != CycleDayKind.expectedPeriod,
            selected: e.period,
            onTap: e.onTogglePeriod,
          ),
          if (cycleKind == CycleDayKind.pms)
            _InfoTile(
              key: const ValueKey('day-card-pms'),
              color: App217Colors.pms(brightness, widget.palette),
              icon: null,
              title: strings.expectedPms,
              value: _cycleDetail(context, view),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _NoteCard(
        key: const ValueKey('day-more-note'),
        strings: strings,
        color: scheme.primary,
        note: note,
        onSave: e.onSaveNote,
      ),
      const SizedBox(height: 22),
      _comingUp(context, view, owner: true),
    ];
  }

  /// A read-only day: the pill, sex and the cycle as tiles, the note as a
  /// card, then what is coming up.
  List<Widget> _readOnlyCards(BuildContext context, DayView view, String note) {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final facts = _dayFacts(
      strings: strings,
      palette: widget.palette,
      brightness: brightness,
      scheme: scheme,
      entry: view.entry,
      note: note,
      cycleKind: view.cycle.kindOf(widget.day),
      cycleDetail: _cycleDetail(context, view),
      isFuture: isFutureDay(widget.day, view.today),
    );
    return [
      _TileGrid(
        children: [
          for (final f in facts.where((f) => f.detail != null))
            _InfoTile(
              key: ValueKey('day-card-${f.id}'),
              color: f.color,
              icon: f.icon,
              title: f.title,
              value: f.detail!,
            ),
        ],
      ),
      if (note.isNotEmpty) ...[
        const SizedBox(height: 10),
        _NoteCard(
          key: const ValueKey('day-more-note'),
          strings: strings,
          color: scheme.primary,
          note: note,
        ),
      ],
      const SizedBox(height: 22),
      _comingUp(context, view, owner: !widget.partner),
    ];
  }

  bool _viewingToday(DayView view) =>
      DateUtils.isSameDay(widget.day, view.today);

  /// "until ~date": the last day of the PMS days or period [widget.day]
  /// falls in.
  String _until(BuildContext context, DayView view) {
    final w = view.cycle.windowAt(widget.day);
    if (w == null) return '';
    final end = view.cycle.kindOf(widget.day) == CycleDayKind.pms
        ? w.pmsEnd
        : w.periodEnd;
    return widget.strings
        .cycleUntilDate(widget.strings.dates.shortDayMonth(end));
  }

  /// What the day's own PMS / expected period card says: "This day", or
  /// for today "Today" and until when it lasts.
  String _cycleDetail(BuildContext context, DayView view) => _viewingToday(view)
      ? '${widget.strings.today}\n${_until(context, view)}'
      : widget.strings.dayThisDay;

  /// The "Coming up" section: a tile for the next PMS window and one for
  /// the next period, or why there are none. What today's own cards already
  /// show (viewing today) is left out.
  Widget _comingUp(BuildContext context, DayView view, {required bool owner}) {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final dates = strings.dates;
    final cycle = view.cycle;
    final todayKind = cycle.kindOf(view.today);
    var next = cycle.nextWindow(view.today);
    // Viewing today during an expected period: that period is on its card,
    // so the next one comes up.
    if (next != null &&
        _viewingToday(view) &&
        todayKind == CycleDayKind.expectedPeriod) {
      next = cycle.windowAfter(next);
    }
    final current = next != null && identical(next, cycle.windowAt(view.today));
    final pmsColor = App217Colors.pms(brightness, widget.palette);
    final periodColor = App217Colors.period(brightness, widget.palette);
    // Same facts as the calendar's header, soonest first.
    final tiles = <Widget>[];
    if (next != null) {
      String until(DateTime d) =>
          strings.cycleUntilDate(dates.shortDayMonth(d));
      if (current && todayKind == CycleDayKind.expectedPeriod) {
        tiles.add(_InfoTile(
          key: const ValueKey('day-coming-period'),
          color: periodColor,
          icon: Icons.water_drop_outlined,
          title: strings.expectedPeriod,
          value: until(next.periodEnd),
        ));
      } else {
        if (current && todayKind == CycleDayKind.pms) {
          // Today's own card says it when today is the day viewed.
          if (!_viewingToday(view)) {
            tiles.add(_InfoTile(
              key: const ValueKey('day-coming-pms'),
              color: pmsColor,
              icon: null,
              title: strings.expectedPms,
              value: until(next.pmsEnd),
            ));
          }
        } else if (next.hasPms) {
          tiles.add(_InfoTile(
            key: const ValueKey('day-coming-pms'),
            color: pmsColor,
            icon: null,
            title: strings.expectedPms,
            value: strings.cycleFromDate(dates.shortDayMonth(next.pmsStart)),
          ));
        }
        tiles.add(_InfoTile(
          key: const ValueKey('day-coming-period'),
          color: periodColor,
          icon: Icons.water_drop_outlined,
          title: strings.expectedPeriod,
          value: '~${dates.shortDayMonth(next.periodStart)}',
        ));
      }
    }
    // Only the period on today's card was predicted: nothing else to say.
    if (tiles.isEmpty && cycle.hasPredictions) return const SizedBox.shrink();
    final stageNote = owner ? strings.cycleStageNote(cycle.note) : '';
    final empty = stageNote.isNotEmpty
        ? stageNote
        : (owner ? strings.cycleHintOwner : strings.cycleNoPredictions);
    return Column(
      key: const ValueKey('day-more-coming-up'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
          child: Text(
            strings.comingUp,
            key: const ValueKey('day-coming-up-title'),
            style: textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (tiles.isEmpty)
          Text(
            empty,
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          _TileGrid(children: tiles),
      ],
    );
  }
}

/// One thing known about a day, as the partner's chips and cards show it.
typedef _DayFact = ({
  String id,
  // Null: the dashed ring expected PMS days have on the calendar.
  IconData? icon,
  Color color,
  String title,
  String label,
  String? detail,
});

List<_DayFact> _dayFacts({
  required Strings strings,
  required AppPalette palette,
  required Brightness brightness,
  required ColorScheme scheme,
  required Entry? entry,
  required String note,
  required CycleDayKind cycleKind,
  required String cycleDetail,
  required bool isFuture,
}) {
  final taken = entry?.taken;
  final period = App217Colors.period(brightness, palette);
  final pms = App217Colors.pms(brightness, palette);
  final heart = App217Colors.intimacy(brightness, palette);
  final pill = switch (taken) {
    true => (
        Icons.check_circle,
        App217Colors.statusTaken(brightness, palette),
        strings.taken
      ),
    false => (
        Icons.cancel,
        App217Colors.statusMissed(brightness, palette),
        strings.missed
      ),
    null => (
        isFuture ? Icons.schedule : Icons.radio_button_unchecked,
        scheme.onSurfaceVariant,
        isFuture ? strings.pillNotDue : strings.pillNotLogged
      ),
  };
  return [
    (
      id: 'pill',
      icon: pill.$1,
      color: pill.$2,
      title: strings.pillLabel,
      label: pill.$3,
      detail: pill.$3,
    ),
    if (entry?.heart ?? false)
      (
        id: 'heart',
        icon: Icons.favorite,
        color: heart,
        title: strings.heartLabel,
        label: strings.heartLabel,
        detail: strings.dayLogged,
      ),
    if (entry?.period ?? false)
      (
        id: 'period',
        icon: Icons.water_drop,
        color: period,
        title: strings.periodLabel,
        label: strings.periodLabel,
        detail: strings.dayLogged,
      )
    else if (cycleKind == CycleDayKind.expectedPeriod)
      (
        id: 'expected-period',
        icon: Icons.water_drop_outlined,
        color: period,
        title: strings.expectedPeriod,
        label: strings.expectedPeriod,
        detail: cycleDetail,
      ),
    if (cycleKind == CycleDayKind.pms)
      (
        id: 'pms',
        icon: null,
        color: pms,
        title: strings.expectedPms,
        label: strings.expectedPms,
        detail: cycleDetail,
      ),
    // The note gets its own full-width card when the sheet is open.
    if (note.isNotEmpty)
      (
        id: 'note',
        icon: Icons.sticky_note_2_outlined,
        color: scheme.primary,
        title: strings.notes,
        label: strings.notes,
        detail: null,
      ),
  ];
}

/// A read-only sheet at rest: a chip for each thing known about the day.
/// Nothing here looks like a control: the day cannot be logged from here.
class _DayChips extends StatelessWidget {
  const _DayChips({
    super.key,
    required this.strings,
    required this.palette,
    required this.entry,
    required this.note,
    required this.cycleKind,
    required this.cycleDetail,
    required this.isFuture,
  });

  final Strings strings;
  final AppPalette palette;
  final Entry? entry;
  final String note;
  final CycleDayKind cycleKind;
  final String cycleDetail;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _dayFacts(
      strings: strings,
      palette: palette,
      brightness: theme.brightness,
      scheme: theme.colorScheme,
      entry: entry,
      note: note,
      cycleKind: cycleKind,
      cycleDetail: cycleDetail,
      isFuture: isFuture,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in facts)
          _InfoChip(
            key: ValueKey('day-chip-${f.id}'),
            icon: f.icon,
            color: f.color,
            label: f.label,
          ),
      ],
    );
  }
}

/// Beside the date of a read-only sheet: why nothing on it can be changed.
class _SheetBadge extends StatelessWidget {
  const _SheetBadge({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Read-only chip: a tinted pill with the mark's colour and its label.
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData? icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.14), scheme.surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FactMark(icon: icon, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Identical square tiles: three to a row where each gets about 100 dp or
/// more, two otherwise, never larger than [maxSide]. The grid as a whole is
/// centred in the room it is given.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  static const gap = 10.0;

  /// Smallest side a three-column row may give its tiles.
  static const minSide = 100.0;

  /// Largest side a tile gets, however wide the sheet.
  static const maxSide = 140.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final three = (width - gap * 2) / 3;
        final cols = three >= minSide ? 3 : 2;
        final side = math.min((width - gap * (cols - 1)) / cols, maxSide);
        // On a sheet wide enough to cap the tiles, centre what is there;
        // on a phone the tiles fill the row from the start.
        final capped = (width - gap * (cols - 1)) / cols > maxSide;
        final used = capped ? math.min(children.length, cols) : cols;
        return Center(
          child: SizedBox(
            width: math.max(1, used) * side + gap * (math.max(1, used) - 1),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in children)
                  SizedBox.square(dimension: side, child: c),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A square tile of the open sheet: icon on top, small title, short value.
///
/// With [onTap] it is one of the owner's controls: a corner mark (+ / check)
/// and a ripple. Without it, it only reads out the day. All tiles of a size
/// share one typography: title and value up to two lines each, ellipsized.
class _InfoTile extends StatelessWidget {
  /// Device text scale a roomy tile's content is clamped to.
  static const maxTextScale = 1.15;

  /// Below this side a tile uses the compact sizes (and no extra text scale).
  static const roomySide = 120.0;

  const _InfoTile({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.value,
    this.muted = false,
    this.onTap,
    this.selected,
  });

  final Color color;
  final IconData? icon;
  final String title;
  final String value;

  /// The value is a prompt, not a fact: drawn in the quieter ink.
  final bool muted;
  final VoidCallback? onTap;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = selected ?? false;
    final fill = Color.alphaBlend(
      color.withValues(alpha: on ? 0.22 : 0.10),
      scheme.surface,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: color.withValues(alpha: on ? 0.9 : (onTap != null ? 0.6 : 0.4)),
        width: on ? 1.5 : 1,
      ),
    );
    final content = LayoutBuilder(
      builder: (context, box) {
        final roomy = box.maxWidth >= roomySide;
        final pad = roomy ? 10.0 : 8.0;
        final badge = roomy ? 30.0 : 24.0;
        final titleStyle = (roomy ? text.labelLarge : text.labelMedium)
            ?.copyWith(color: scheme.onSurfaceVariant, height: 1.15);
        final valueStyle = text.titleSmall?.copyWith(
          fontSize: roomy ? null : 13,
          color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
          fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
          height: 1.15,
        );
        return Padding(
          padding: EdgeInsets.all(pad),
          // A fixed square cannot grow with the device's text size.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: roomy ? maxTextScale : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: on ? 0.3 : 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _FactMark(
                          icon: icon,
                          color: color,
                          size: roomy ? 18 : 16,
                        ),
                      ),
                    ),
                    if (onTap != null) _toggleMark(roomy ? 22 : 20),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (onTap == null) {
      return Semantics(
        label: '$title, $value',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: fill, shape: shape),
          child: content,
        ),
      );
    }
    return Semantics(
      button: true,
      toggled: selected,
      label: '$title, $value',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fill,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }

  Widget _toggleMark(double size) {
    final selected = this.selected ?? false;
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF0B1220);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Icon(
        selected ? Icons.check : Icons.add,
        size: 14,
        color: selected ? ink : color,
      ),
    );
  }
}

/// Card of the open sheet (the note): a tinted icon, a small title and [body].
///
/// With [onTap] it is one of the owner's controls: a firmer border, a
/// pencil in the corner and a ripple. Without it, it only reads out the day.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
    this.semanticsLabel,
    this.corner,
  });

  final Color color;
  final IconData? icon;
  final String title;
  final Widget body;
  final VoidCallback? onTap;

  /// Top-right of the title; a pencil by default when [onTap] is set.
  final Widget? corner;

  /// What a screen reader announces for a tappable card (else [title]).
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onTap = this.onTap;
    final fill = Color.alphaBlend(
      color.withValues(alpha: 0.10),
      scheme.surface,
    );
    final border = BorderSide(
      color: color.withValues(alpha: onTap != null ? 0.6 : 0.4),
    );
    final titleText = Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
    );
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: _FactMark(icon: icon, color: color, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (corner == null && onTap == null)
                  titleText
                else
                  Row(
                    children: [
                      Expanded(child: titleText),
                      const SizedBox(width: 6),
                      corner ?? _cornerMark(context),
                    ],
                  ),
                const SizedBox(height: 2),
                body,
              ],
            ),
          ),
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: border,
    );
    if (onTap == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: shape),
        child: content,
      );
    }
    return Semantics(
      button: true,
      label: semanticsLabel ?? title,
      // A control in the corner (the note's pencil) stays reachable.
      excludeSemantics: corner == null,
      onTap: onTap,
      child: Material(
        color: fill,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }

  /// Top-right mark of a tappable card: what a tap will do.
  Widget _cornerMark(BuildContext context) =>
      Icon(Icons.edit_outlined, size: 18, color: color);
}

/// The open sheet's note card. A long note shows its first lines and a tap
/// unfolds the rest. With [onSave] (the owner's editable day) the note is
/// written right in the card: a tap on a short (or empty) note, or on the
/// pencil, turns it into a field with Cancel and Save.
class _NoteCard extends StatefulWidget {
  const _NoteCard({
    super.key,
    required this.strings,
    required this.color,
    required this.note,
    this.onSave,
  });

  final Strings strings;
  final Color color;
  final String note;
  final ValueChanged<String>? onSave;

  /// Lines a folded note shows.
  static const foldedLines = 4;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _expanded = false;
  TextEditingController? _field;

  /// The keyboard height the open field was last brought into view for.
  double? _shownAbove;

  /// Brings the whole card (field, Cancel and Save) into the sheet's view.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _field == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  void dispose() {
    _field?.dispose();
    super.dispose();
  }

  void _edit() {
    setState(() {
      _field = TextEditingController(text: widget.note)
        ..selection = TextSelection.collapsed(offset: widget.note.length);
    });
  }

  void _close() {
    final field = _field;
    _shownAbove = null;
    setState(() => _field = null);
    // After the frame: the field still holds it until it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => field?.dispose());
  }

  void _save() {
    final text = _field?.text.trim() ?? '';
    _close();
    if (text != widget.note) widget.onSave?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final noteStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
      fontSize: 17,
      height: 1.35,
    );
    final field = _field;
    if (field != null) {
      // Once on opening, and again as the keyboard comes up.
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (_shownAbove != inset) {
        _shownAbove = inset;
        _reveal();
      }
      return _InfoCard(
        color: widget.color,
        icon: Icons.sticky_note_2_outlined,
        title: strings.notes,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('day-note-field'),
              controller: field,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              style: noteStyle,
              decoration: InputDecoration(
                hintText: strings.addNote,
                isDense: true,
                filled: true,
                fillColor: scheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.color, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // The theme stretches buttons, so each gets half the row.
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('day-note-cancel'),
                    onPressed: _close,
                    child: Text(strings.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('day-note-save'),
                    onPressed: _save,
                    child: Text(strings.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final note = widget.note;
    final onSave = widget.onSave;
    if (note.isEmpty) {
      return _InfoCard(
        color: widget.color,
        icon: Icons.sticky_note_2_outlined,
        title: strings.notes,
        body: Text(
          strings.addNote,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        onTap: onSave == null ? null : _edit,
        semanticsLabel: strings.addNote,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // The text's width inside the card: padding, icon and gap.
        final width = math.max(0.0, constraints.maxWidth - 14 * 2 - 36 - 12);
        final painter = TextPainter(
          text: TextSpan(text: note, style: noteStyle),
          maxLines: _NoteCard.foldedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: width);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        final folded = long && !_expanded;
        final VoidCallback? onTap = long
            ? () => setState(() => _expanded = !_expanded)
            : (onSave == null ? null : _edit);
        final Widget? corner;
        if (onSave != null) {
          corner = IconButton(
            key: const ValueKey('day-note-edit'),
            tooltip: strings.editNote,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 24),
            iconSize: 18,
            color: widget.color,
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          );
        } else if (long) {
          corner = Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: widget.color,
          );
        } else {
          corner = null;
        }
        return _InfoCard(
          color: widget.color,
          icon: Icons.sticky_note_2_outlined,
          title: strings.notes,
          corner: corner,
          body: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note,
                  maxLines: folded ? _NoteCard.foldedLines : null,
                  overflow: folded ? TextOverflow.ellipsis : null,
                  style: noteStyle,
                ),
                if (long)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _expanded ? strings.daySheetLess : strings.daySheetMore,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: widget.color),
                    ),
                  ),
              ],
            ),
          ),
          onTap: onTap,
          semanticsLabel: long
              ? '${strings.notes}: $note. '
                  '${_expanded ? strings.showLessNote : strings.showMoreNote}'
              : '${strings.notes}: $note. ${strings.editNote}',
        );
      },
    );
  }
}

/// A fact's icon, or the dashed PMS ring when it has none.
class _FactMark extends StatelessWidget {
  const _FactMark(
      {required this.icon, required this.color, required this.size});

  final IconData? icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon != null) return Icon(icon, size: size, color: color);
    return CustomPaint(
      size: Size.square(size - 4),
      painter: DashedRingPainter(
        color: color,
        radius: size / 4,
        strokeWidth: 1.6,
        dash: 2.5,
        gap: 2.5,
      ),
    );
  }
}

/// Closes the route [context] belongs to, whatever is on top of it now
/// (a plain pop would close the wrong route).
void closeOwnRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  final navigator = route?.navigator;
  if (route == null || navigator == null || !route.isActive) return;
  if (route.isCurrent) {
    navigator.pop();
  } else {
    navigator.removeRoute(route);
  }
}

/// Closes the route it sits in when [signal] changes.
class CloseOnSignal extends StatefulWidget {
  const CloseOnSignal({super.key, required this.signal, required this.child});

  final ValueListenable<int> signal;
  final Widget child;

  @override
  State<CloseOnSignal> createState() => CloseOnSignalState();
}

class CloseOnSignalState extends State<CloseOnSignal> {
  late int _opened;

  @override
  void initState() {
    super.initState();
    _opened = widget.signal.value;
    widget.signal.addListener(_check);
  }

  @override
  void didUpdateWidget(covariant CloseOnSignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.signal, widget.signal)) {
      oldWidget.signal.removeListener(_check);
      _opened = widget.signal.value;
      widget.signal.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.signal.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (widget.signal.value != _opened && mounted) closeOwnRoute(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
