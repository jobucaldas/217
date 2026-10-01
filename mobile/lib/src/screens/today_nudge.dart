import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models.dart';
import '../prefs.dart';

/// Floating “record today” control: magnetically sticks to a side edge,
/// drags vertically, and persists side + bottom inset.
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

  @override
  State<TodayNudge> createState() => _TodayNudgeState();
}

class _TodayNudgeState extends State<TodayNudge> {
  late final AppearancePrefs _prefs = widget.prefs ?? AppearancePrefs();
  bool _right = true;
  double _bottom = 16;
  bool _ready = false;
  double _dragDx = 0;

  bool get visible => TodayNudge.isVisible(widget.todayEntry);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pos = await _prefs.loadFabPosition();
    if (!mounted) return;
    setState(() {
      _right = pos.right;
      _bottom = pos.bottom;
      _ready = true;
    });
  }

  Future<void> _persist() =>
      _prefs.saveFabPosition(right: _right, bottom: _bottom);

  void _onPanUpdate(DragUpdateDetails details, double maxBottom) {
    setState(() {
      _bottom = (_bottom - details.delta.dy).clamp(8.0, maxBottom);
      _dragDx += details.delta.dx;
    });
  }

  void _onPanEnd(double viewWidth) {
    // Magnet to nearer horizontal edge from cumulative drag / current side.
    final flipThreshold = viewWidth * 0.18;
    if (_dragDx.abs() > flipThreshold) {
      // Positive dx = dragged toward the right edge.
      setState(() => _right = _dragDx > 0);
    }
    _dragDx = 0;
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxBottom = (media.size.height - media.padding.top - 120)
        .clamp(48.0, media.size.height);
    final bottom = _ready ? _bottom.clamp(8.0, maxBottom) : 16.0;

    return Positioned(
      left: _right ? null : 16,
      right: _right ? 16 : null,
      bottom: bottom + media.padding.bottom,
      child: GestureDetector(
        onPanUpdate: (d) => _onPanUpdate(d, maxBottom),
        onPanEnd: (_) => _onPanEnd(media.size.width),
        child: Material(
          elevation: 10,
          color: scheme.primaryContainer,
          shadowColor: scheme.shadow.withValues(alpha: 0.55),
          surfaceTintColor: scheme.primary.withValues(alpha: 0.12),
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: widget.onRecord,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.strings.recordToday,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
