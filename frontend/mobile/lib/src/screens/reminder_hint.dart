import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';

/// Dismissible calendar bubble pointing at the reminder setting. Closes
/// itself after [autoDismissAfter], long enough to read one short sentence.
class ReminderHint extends StatefulWidget {
  const ReminderHint({
    super.key,
    required this.strings,
    required this.onDismiss,
    this.autoDismissAfter = const Duration(seconds: 10),
  });

  final Strings strings;
  final VoidCallback onDismiss;
  final Duration autoDismissAfter;

  @override
  State<ReminderHint> createState() => _ReminderHintState();
}

class _ReminderHintState extends State<ReminderHint> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoDismissAfter, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: scheme.onSecondaryContainer, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.strings.reminderHint,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('reminder-hint-dismiss'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSecondaryContainer,
              ),
              onPressed: widget.onDismiss,
              child: Text(widget.strings.reminderHintDismiss),
            ),
          ],
        ),
      ),
    );
  }
}
