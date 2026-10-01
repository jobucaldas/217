import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models.dart';

/// Bottom-end reminder chip for an unrecorded today.
/// Hidden once today has an entry (taken or missed).
class TodayNudge extends StatelessWidget {
  const TodayNudge({
    super.key,
    required this.strings,
    required this.todayEntry,
    required this.onRecord,
  });

  final Strings strings;
  final Entry? todayEntry;
  final VoidCallback onRecord;

  /// Mid-screen hero CTA is never used; chip only when still open.
  bool get visible => todayEntry == null;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          elevation: 3,
          color: scheme.primaryContainer,
          shadowColor: scheme.shadow.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onRecord,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: scheme.onPrimaryContainer, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    strings.recordToday,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
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
