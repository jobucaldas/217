import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';

/// Floating “update today” control: text-hugging pill + plus on the outer
/// top corner (flips with L/R magnet), idle settle bounce, edge snap.
class TodayNudge extends StatefulWidget {
  const TodayNudge({
    super.key,
    required this.strings,
    required this.todayEntry,
    required this.onRecord,
    this.prefs,
  });

  final Strings strings;
  final Entry? todayEntry;
  final VoidCallback onRecord;
  final AppearancePrefs? prefs;

  /// Mid-screen hero CTA is never used; chip only when still open.
  static bool isVisible(Entry? todayEntry) =>
      todayEntry == null || todayEntry.taken == null;

  /// Pill height (logical px).
  static const double pillHeight = 56;

  /// Plus accessory diameter (logical px).
  static const double plusSize = 32;

  /// How far the plus overhangs past the pill’s outer top corner.
  static const double plusOverhang = 12;

  /// Horizontal padding inside the text pill.
  static const double pillPadX = 24;

  /// Label font size (logical px).
  static const double labelSize = 16;

  /// Total control height including corner plus overhang.
  static double get height => pillHeight + plusOverhang;

  /// Intrinsic control width for [label] with [style] (magnet math).
  static double widthForLabel(String label, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style ??
            const TextStyle(
              fontSize: labelSize,
              fontWeight: FontWeight.w700,
            ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Pill hugs text; outer corner plus overhangs past one end.
    return pillPadX * 2 + painter.width + plusOverhang * 0.4;
  }

  @override
  State<TodayNudge> createState() => _TodayNudgeState();
}

class _TodayNudgeState extends State<TodayNudge> with TickerProviderStateMixin {
  late final AppearancePrefs _prefs = widget.prefs ?? AppearancePrefs();
  late final AnimationController _float;
  late final Animation<double> _floatDy;
  late final AnimationController _snap;

  bool _right = true;
  double _bottom = 16;
  bool _ready = false;
  bool _dragging = false;
  double _dragDx = 0;
  Animation<double>? _snapSide;

  bool get visible => TodayNudge.isVisible(widget.todayEntry);

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 860),
    );
    // One-shot settle bounce: reads as floating, then rests.
    _floatDy = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -5).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -5, end: 3).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 3, end: -1.5).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -1.5, end: 0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 22,
      ),
    ]).animate(_float);
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _load();
  }

  @override
  void dispose() {
    _float.dispose();
    _snap.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pos = await _prefs.loadFabPosition();
    if (!mounted) return;
    setState(() {
      _right = pos.right;
      _bottom = pos.bottom;
      _ready = true;
    });
    await _float.forward(from: 0);
  }

  Future<void> _persist() =>
      _prefs.saveFabPosition(right: _right, bottom: _bottom);

  void _onPanStart(DragStartDetails _) {
    _snap.stop();
    _snapSide = null;
    setState(() {
      _dragging = true;
      _dragDx = 0;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, double maxBottom) {
    setState(() {
      _bottom = (_bottom - details.delta.dy).clamp(8.0, maxBottom);
      _dragDx += details.delta.dx;
    });
  }

  void _onPanEnd(double viewWidth, double controlWidth) {
    final minLeft = 16.0;
    final maxLeft =
        (viewWidth - 16 - controlWidth).clamp(minLeft, viewWidth);
    final base = _right ? maxLeft : minLeft;
    final currentLeft = (base + _dragDx).clamp(minLeft, maxLeft);
    final mid = (minLeft + maxLeft) / 2;
    final targetRight = currentLeft >= mid;
    final begin = maxLeft == minLeft
        ? (targetRight ? 1.0 : 0.0)
        : (currentLeft - minLeft) / (maxLeft - minLeft);
    final end = targetRight ? 1.0 : 0.0;

    HapticFeedback.selectionClick();
    setState(() {
      _right = targetRight;
      _dragDx = 0;
      _dragging = false;
      _snapSide = Tween<double>(begin: begin, end: end).animate(
        CurvedAnimation(parent: _snap, curve: Curves.easeOutBack),
      );
    });
    _snap.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _snapSide = null);
      _persist();
    });
  }

  double _leftFor(double viewWidth, double controlWidth) {
    final minLeft = 16.0;
    final maxLeft =
        (viewWidth - 16 - controlWidth).clamp(minLeft, viewWidth);
    if (_dragging) {
      final base = _right ? maxLeft : minLeft;
      return (base + _dragDx).clamp(minLeft, maxLeft);
    }
    if (_snapSide != null) {
      return minLeft + (maxLeft - minLeft) * _snapSide!.value;
    }
    return _right ? maxLeft : minLeft;
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxBottom = (media.size.height - media.padding.top - 120)
        .clamp(48.0, media.size.height);
    final bottom = _ready ? _bottom.clamp(8.0, maxBottom) : 16.0;
    final floatDy = _dragging ? 0.0 : _floatDy.value;
    final label = widget.strings.updateToday;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
          fontSize: TodayNudge.labelSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        );
    final controlWidth = TodayNudge.widthForLabel(label, labelStyle);
    // Outer top corner: right edge → top-right; left edge → top-left.
    final plusOnRight = _right;

    return AnimatedBuilder(
      animation: Listenable.merge([_float, _snap]),
      builder: (context, _) {
        return Positioned(
          left: _leftFor(media.size.width, controlWidth),
          bottom: bottom + media.padding.bottom - floatDy,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: (d) => _onPanUpdate(d, maxBottom),
            onPanEnd: (_) => _onPanEnd(media.size.width, controlWidth),
            child: Tooltip(
              message: label,
              child: IntrinsicWidth(
                child: SizedBox(
                  key: const ValueKey('today-nudge-control'),
                  height: TodayNudge.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: TodayNudge.plusOverhang,
                          left: plusOnRight ? 0 : TodayNudge.plusOverhang * 0.35,
                          right:
                              plusOnRight ? TodayNudge.plusOverhang * 0.35 : 0,
                        ),
                        child: Material(
                          elevation: 10,
                          color: scheme.primaryContainer,
                          shadowColor: scheme.shadow.withValues(alpha: 0.5),
                          surfaceTintColor:
                              scheme.primary.withValues(alpha: 0.12),
                          shape: const StadiumBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: widget.onRecord,
                            customBorder: const StadiumBorder(),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: TodayNudge.pillHeight,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: TodayNudge.pillPadX,
                                  vertical: 16,
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: labelStyle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: plusOnRight ? null : 0,
                        right: plusOnRight ? 0 : null,
                        top: 0,
                        child: Material(
                          elevation: 14,
                          color: scheme.primary,
                          shadowColor: scheme.shadow.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: widget.onRecord,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: TodayNudge.plusSize,
                              height: TodayNudge.plusSize,
                              child: Icon(
                                Icons.add,
                                color: scheme.onPrimary,
                                size: 20,
                                semanticLabel: label,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
