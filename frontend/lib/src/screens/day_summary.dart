import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  });

  final Strings strings;
  final DateTime day;
  final bool isToday;
  final Entry? entry;
  final CycleDayKind cycleKind;
  final AppPalette palette;

  /// Null on read-only calendars: tags only, no button.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final shortDay = DateFormat.MMMd(strings.dateLocale).format(day);
    final taken = entry?.taken;
    final period = App217Colors.period(brightness, palette);
    final loggedPeriod = entry?.period ?? false;

    final tags = <Widget>[
      if (taken == null)
        _DayTag(
          key: const ValueKey('day-tag-status'),
          label: strings.unrecorded,
          color: scheme.onSurfaceVariant,
          mark: DayMark(color: scheme.onSurfaceVariant, outlined: true),
        )
      else
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
          label: strings.legendPms,
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
      if (entry != null && entry!.notes.trim().isNotEmpty)
        _DayTag(
          key: const ValueKey('day-tag-note'),
          label: strings.notes,
          color: scheme.primary,
          mark: DayMark(
            color: scheme.primary,
            icon: Icons.sticky_note_2_outlined,
          ),
        ),
    ];

    final tagWrap = Wrap(
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
    // Short or wide windows (landscape, desktop) put the button beside the
    // tags so the month grid keeps its height.
    final size = MediaQuery.sizeOf(context);
    final compact = size.width >= 600 || size.height < 600;
    final button = onEdit == null
        ? null
        : FilledButton.icon(
            key: const ValueKey('update-day-button'),
            onPressed: onEdit,
            // The theme's full-width minimum would not fit beside the tags.
            style: compact
                ? FilledButton.styleFrom(minimumSize: const Size(0, 48))
                : null,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(
              isToday ? strings.updateToday : strings.updateDay(shortDay),
            ),
          );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, compact ? 8 : 12),
        child: compact
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
              ),
      ),
    );
  }
}

/// Rounded tag tinted with the mark's colour; the label stays on-surface ink
/// so it reads in both themes.
class _DayTag extends StatelessWidget {
  const _DayTag({
    super.key,
    required this.label,
    required this.color,
    required this.mark,
  });

  final String label;
  final Color color;
  final Widget mark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.14), scheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// The selected day's note, drawn in the room the month grid leaves below
/// itself. Display only: swipes pass through to the month carousel.
class DayNotePanel extends StatelessWidget {
  const DayNotePanel({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = text.bodyLarge?.copyWith(color: scheme.onSurface);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same text scaling the Text below gets from the device setting.
          final lineHeight = MediaQuery.textScalerOf(context)
                  .scale(style?.fontSize ?? 17) *
              (style?.height ?? 1.4);
          // 24px of vertical padding inside the panel.
          final maxLines =
              ((constraints.maxHeight - 24) / lineHeight).floor().clamp(1, 12);
          return Align(
            alignment: Alignment.topCenter,
            child: Container(
              key: const ValueKey('day-note'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.55),
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
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notes,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ],
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
