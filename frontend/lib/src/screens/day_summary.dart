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
