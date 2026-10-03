import 'package:flutter/material.dart';

/// Buttons of a dialog on one row: the main action takes most of the width
/// and the secondary one (cancel, clear…) is a plain link beside it, never
/// wrapped onto its own line.
class DialogActionRow extends StatelessWidget {
  const DialogActionRow({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (secondary != null) ...[
          Expanded(child: secondary!),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 2, child: primary),
      ],
    );
  }
}

/// Text-only secondary action, red by default. Use [neutral] when the main
/// action is already red (destructive confirmations).
class DialogLinkButton extends StatelessWidget {
  const DialogLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.neutral = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: neutral ? scheme.onSurface : scheme.error,
        minimumSize: const Size(0, 48),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
