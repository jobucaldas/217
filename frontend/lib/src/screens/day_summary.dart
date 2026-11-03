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

  /// Future days show only what is expected. The button stays (so the grid
  /// keeps its height) but is disabled: nothing can be logged ahead of time.
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
      else if (cycleKind == CycleDayKind.predictedPeriod)
        _DayTag(
          key: const ValueKey('day-tag-predicted-period'),
          label: strings.predictedPeriod,
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
    final viewing = onEdit == null && onView != null;
    final button = onEdit == null && onView == null
        ? null
        : FilledButton.icon(
            key: ValueKey(viewing ? 'view-day-button' : 'update-day-button'),
            // Viewing stays enabled on future days: they show predictions.
            onPressed: viewing ? onView : (isFuture ? null : onEdit),
            // The theme's full-width minimum would not fit beside the tags.
            style: compact
                ? FilledButton.styleFrom(minimumSize: const Size(0, 48))
                : null,
            icon: Icon(viewing
                ? Icons.visibility_outlined
                : Icons.edit_calendar_outlined),
            label: Text(viewing
                ? (isToday ? strings.viewToday : strings.viewDay(shortDay))
                : (isToday ? strings.updateToday : strings.updateDay(shortDay))),
          );

    final barHeight = compact ? 48.0 : 52.0;
    final jump = onJumpToToday == null
        ? null
        : SizedBox.square(
            dimension: barHeight,
            child: IconButton.filledTonal(
              key: const ValueKey('jump-to-today-button'),
              // Square, with the corners of the update-day button beside it.
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              tooltip: strings.jumpToToday,
              onPressed: onJumpToToday,
              icon: const Icon(Icons.today),
            ),
          );
    final actions = button == null && jump == null
        ? null
        : Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (button != null)
                if (compact) button else Expanded(child: button),
              if (button != null && jump != null) const SizedBox(width: 8),
              if (jump != null) jump,
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
              DayNotePanel(notes: note, maxLines: 3, onTap: onOpenNote),
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
            alignment: Alignment.centerLeft,
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
  });

  final String notes;

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
          return Align(
            alignment: alignment,
            child: onTap == null
                ? panel
                : Semantics(
                    button: true,
                    child: Material(
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialogContext.mounted) Navigator.of(dialogContext).maybePop();
            });
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

/// A day sheet that can be pulled up. At rest it is the owner's editor
/// ([sheet]) or, for a partner, a read-only glance at the day; pulled up it
/// also shows the day in detail, the whole note and what is coming up.
/// Dragging anywhere on it (or tapping its handle) opens and closes it;
/// swiping it down past its resting height dismisses it.
class ExpandableDaySheet extends StatefulWidget {
  const ExpandableDaySheet({
    super.key,
    required this.strings,
    required this.palette,
    required this.day,
    required this.today,
    required this.notes,
    required this.cycle,
    this.sheet,
    this.entry,
  });

  final Strings strings;
  final AppPalette palette;
  final DateTime day;
  final DateTime today;

  /// The day's note, followed live (the owner can change it from [sheet]).
  final ValueListenable<String> notes;
  final CycleInfo cycle;

  /// The owner's editor, shown at rest. Null on a partner's (read-only)
  /// calendar: the sheet then describes [entry] instead.
  final Widget? sheet;

  /// What was logged for [day]; read by the partner's glance and cards.
  final Entry? entry;

  @override
  State<ExpandableDaySheet> createState() => _ExpandableDaySheetState();
}

class _ExpandableDaySheetState extends State<ExpandableDaySheet> {
  final _controller = DraggableScrollableController();
  final _restingKey = GlobalKey();
  final _contentKey = GlobalKey();

  /// Measured heights of the part shown at rest and of everything.
  double? _restingPx;
  double? _contentPx;

  /// Sheet sizes, as fractions of the room the modal gives it.
  double _resting = 0.25;
  double _max = 0.7;
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Fits the resting and open sizes to what was laid out.
  void _measure() {
    if (!mounted) return;
    final resting = _restingKey.currentContext?.size?.height;
    final content = _contentKey.currentContext?.size?.height;
    if (resting == null || content == null) return;
    bool differs(double? a, double b) => a == null || (a - b).abs() > 0.5;
    if (differs(_restingPx, resting) || differs(_contentPx, content)) {
      setState(() {
        _restingPx = resting;
        _contentPx = content;
      });
    }
  }

  void _toggle() {
    if (!_controller.isAttached || _max <= _resting) return;
    _controller.animateTo(
      _open ? _resting : _max,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onExtent(DraggableScrollableNotification n) {
    final open = n.extent > (_resting + _max) / 2;
    if (open != _open) setState(() => _open = open);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.notes,
      builder: (context, note, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return _build(context, note);
      },
    );
  }

  Widget _build(BuildContext context, String note) {
    final scheme = Theme.of(context).colorScheme;
    final strings = widget.strings;
    final readOnly = widget.sheet == null;
    final more = readOnly ? _partnerCards(context, note) : _ownerMore(context, note);
    final handle = Semantics(
      button: true,
      label: _open ? strings.daySheetLess : strings.daySheetMore,
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
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final resting = Column(
      key: _restingKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        handle,
        widget.sheet ??
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: _PartnerDayGlance(
                strings: strings,
                palette: widget.palette,
                day: widget.day,
                entry: widget.entry,
                note: note,
                cycleKind: widget.cycle.kindOf(widget.day),
                isFuture: widget.day.isAfter(widget.today),
              ),
            ),
        // Keeps the resting sheet clear of the system navigation bar.
        SizedBox(height: bottomInset),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final padding = MediaQuery.paddingOf(context);
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // First frame: estimates until the parts are measured.
        final restingPx = _restingPx ?? 170 * scale + padding.bottom;
        final contentPx = _contentPx ?? height;
        final top = ((height - padding.top - 24) / height).clamp(0.3, 1.0);
        _resting = (restingPx / height).clamp(0.1, top);
        _max = (contentPx / height).clamp(_resting, top);
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: _onExtent,
          child: DraggableScrollableSheet(
            controller: _controller,
            expand: false,
            snap: true,
            initialChildSize: _resting,
            // Below the resting size is only the way out: the modal closes
            // once the sheet reaches 0.
            minChildSize: 0,
            maxChildSize: _max,
            snapSizes: [_resting],
            builder: (context, controller) => Material(
              color: scheme.surfaceContainerLow,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                key: const ValueKey('expandable-day-sheet'),
                controller: controller,
                // Content shorter than the sheet still has to take the drag,
                // or the sheet could never be pulled up.
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  key: _contentKey,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    resting,
                    Padding(
                      key: const ValueKey('day-more'),
                      padding:
                          EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: more,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The owner's sheet already shows what she logged: pulled up it adds the
  /// day's predictions, the whole note and what is coming up.
  List<Widget> _ownerMore(BuildContext context, String note) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final period = App217Colors.period(brightness, widget.palette);
    final pms = App217Colors.pms(brightness, widget.palette);
    final cycleKind = widget.cycle.kindOf(widget.day);

    Widget row(Key key, String label, Widget mark) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 20, child: Center(child: mark)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface)),
            ),
          ]),
        );

    return [
      if (cycleKind == CycleDayKind.predictedPeriod)
        row(
          const ValueKey('day-more-predicted-period'),
          widget.strings.predictedPeriod,
          DayMark(color: period, icon: Icons.water_drop_outlined),
        ),
      if (cycleKind == CycleDayKind.pms)
        row(
          const ValueKey('day-more-pms'),
          widget.strings.expectedPms,
          DayMark(color: pms, dashed: true),
        ),
      if (note.isNotEmpty)
        Container(
          key: const ValueKey('day-more-note'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              scheme.onSurface.withValues(alpha: 0.06),
              scheme.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline),
          ),
          child: Text(
            note,
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurface,
              fontSize: 17,
              height: 1.35,
            ),
          ),
        ),
      const SizedBox(height: 10),
      _comingUpCard(context, owner: true),
    ];
  }

  /// The partner's day, card by card: the pill, sex, the cycle, the note,
  /// then what is coming up.
  List<Widget> _partnerCards(BuildContext context, String note) {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final facts = _dayFacts(
      strings: strings,
      palette: widget.palette,
      brightness: brightness,
      scheme: scheme,
      entry: widget.entry,
      note: note,
      cycleKind: widget.cycle.kindOf(widget.day),
      isFuture: widget.day.isAfter(widget.today),
    );
    final small = facts.where((f) => f.detail != null).toList();
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          // Two to a row; a lone last card takes the whole row.
          final half = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < small.length; i++)
                SizedBox(
                  width: i == small.length - 1 && small.length.isOdd
                      ? constraints.maxWidth
                      : half,
                  child: _InfoCard(
                    key: ValueKey('day-card-${small[i].id}'),
                    color: small[i].color,
                    icon: small[i].icon,
                    title: small[i].title,
                    body: Text(
                      small[i].detail!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      if (note.isNotEmpty) ...[
        const SizedBox(height: 10),
        _InfoCard(
          key: const ValueKey('day-more-note'),
          color: scheme.primary,
          icon: Icons.sticky_note_2_outlined,
          title: strings.notes,
          body: Text(
            note,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 17,
                  height: 1.35,
                ),
          ),
        ),
      ],
      const SizedBox(height: 10),
      _comingUpCard(context, owner: false),
    ];
  }

  /// The next PMS window and period, or why there are none.
  Widget _comingUpCard(BuildContext context, {required bool owner}) {
    final strings = widget.strings;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final dates = strings.dates;
    final cycle = widget.cycle;
    final next = cycle.nextWindow(widget.today);
    final todayKind = cycle.kindOf(widget.today);
    final pmsMark = DayMark(
      color: App217Colors.pms(brightness, widget.palette),
      dashed: true,
    );
    final periodMark = DayMark(
      color: App217Colors.period(brightness, widget.palette),
      icon: Icons.water_drop_outlined,
    );
    // Same lines as the calendar's header, soonest first.
    final lines = <(Widget, String)>[];
    if (next != null) {
      if (todayKind == CycleDayKind.predictedPeriod) {
        lines.add((periodMark, strings.cyclePeriodNow));
      } else {
        if (todayKind == CycleDayKind.pms) {
          lines.add((pmsMark, strings.cyclePmsLikelyNow));
        } else if (next.pmsStart.year >= 2) {
          lines.add((
            pmsMark,
            strings.cyclePmsFrom(dates.shortDayMonth(next.pmsStart)),
          ));
        }
        lines.add((
          periodMark,
          strings.cycleNextPeriod(dates.shortDayMonth(next.periodStart)),
        ));
      }
    }
    final stageNote = owner ? strings.cycleStageNote(cycle.note) : '';
    final empty = stageNote.isNotEmpty
        ? stageNote
        : (owner ? strings.cycleHintOwner : strings.cycleNoPredictions);
    final style = textTheme.bodyLarge?.copyWith(color: scheme.onSurface);
    return _InfoCard(
      key: const ValueKey('day-more-coming-up'),
      color: scheme.primary,
      icon: Icons.event_outlined,
      title: strings.comingUp,
      body: lines.isEmpty
          ? Text(empty, style: style)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (mark, text) in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      SizedBox(width: 16, child: Center(child: mark)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(text, style: style)),
                    ]),
                  ),
              ],
            ),
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
    else if (cycleKind == CycleDayKind.predictedPeriod)
      (
        id: 'predicted-period',
        icon: Icons.water_drop_outlined,
        color: period,
        title: strings.predictedPeriod,
        label: strings.predictedPeriod,
        detail: strings.periodExpectedThisDay,
      ),
    if (cycleKind == CycleDayKind.pms)
      (
        id: 'pms',
        icon: null,
        color: pms,
        title: strings.expectedPms,
        label: strings.expectedPms,
        detail: strings.pmsLikelyThisDay,
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

/// The partner's sheet at rest: the date and a chip for each thing known
/// about the day. Nothing here looks like a control: the day is hers.
class _PartnerDayGlance extends StatelessWidget {
  const _PartnerDayGlance({
    required this.strings,
    required this.palette,
    required this.day,
    required this.entry,
    required this.note,
    required this.cycleKind,
    required this.isFuture,
  });

  final Strings strings;
  final AppPalette palette;
  final DateTime day;
  final Entry? entry;
  final String note;
  final CycleDayKind cycleKind;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final facts = _dayFacts(
      strings: strings,
      palette: palette,
      brightness: theme.brightness,
      scheme: scheme,
      entry: entry,
      note: note,
      cycleKind: cycleKind,
      isFuture: isFuture,
    );
    return Padding(
      key: const ValueKey('partner-day-glance'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.dates.fullDate(day), style: theme.textTheme.headlineMedium),
          const SizedBox(height: 14),
          Wrap(
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
          ),
        ],
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

/// Read-only card of the open sheet: a tinted icon, a small title and
/// [body].
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color color;
  final IconData? icon;
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), scheme.surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
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
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                body,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A fact's icon, or the dashed PMS ring when it has none.
class _FactMark extends StatelessWidget {
  const _FactMark({required this.icon, required this.color, required this.size});

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

/// Pops the dialog it sits in when [signal] changes.
class CloseOnSignal extends StatefulWidget {
  const CloseOnSignal({super.key, required this.signal, required this.child});

  final ValueListenable<int> signal;
  final Widget child;

  @override
  State<CloseOnSignal> createState() => CloseOnSignalState();
}

class CloseOnSignalState extends State<CloseOnSignal> {
  late final int _opened;

  @override
  void initState() {
    super.initState();
    _opened = widget.signal.value;
    widget.signal.addListener(_check);
  }

  @override
  void dispose() {
    widget.signal.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (widget.signal.value != _opened && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
