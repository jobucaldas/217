import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';

/// Floating “record today” control: circular plus, idle settle bounce,
/// magnetic edge snap, persists side + bottom inset.
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
  static bool isVisible(Entry? todayEntry) => todayEntry == null;

  /// Circular hit target diameter (logical px).
  static const double size = 64;

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

  void _onPanEnd(double viewWidth) {
    final minLeft = 16.0;
    final maxLeft = (viewWidth - 16 - TodayNudge.size).clamp(minLeft, viewWidth);
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

  double _leftFor(double viewWidth) {
    final minLeft = 16.0;
    final maxLeft = (viewWidth - 16 - TodayNudge.size).clamp(minLeft, viewWidth);
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

    return AnimatedBuilder(
      animation: Listenable.merge([_float, _snap]),
      builder: (context, _) {
        return Positioned(
          left: _leftFor(media.size.width),
          bottom: bottom + media.padding.bottom - floatDy,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: (d) => _onPanUpdate(d, maxBottom),
            onPanEnd: (_) => _onPanEnd(media.size.width),
            child: Tooltip(
              message: widget.strings.recordToday,
              child: Material(
                elevation: 12,
                color: scheme.primaryContainer,
                shadowColor: scheme.shadow.withValues(alpha: 0.55),
                surfaceTintColor: scheme.primary.withValues(alpha: 0.14),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onRecord,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: TodayNudge.size,
                    height: TodayNudge.size,
                    child: Icon(
                      Icons.add,
                      color: scheme.onPrimaryContainer,
                      size: 30,
                      semanticLabel: widget.strings.recordToday,
                    ),
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
