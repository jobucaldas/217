import 'package:flutter/material.dart';

import '../i18n.dart';

/// "Messages" switch, shown next to the pill notifications
/// (owner reminders, partner alerts). Keeps its own copy of the value: the
/// screen hosting it is pushed once and does not rebuild with app state.
class MessageNotificationsTile extends StatefulWidget {
  const MessageNotificationsTile({
    super.key,
    required this.strings,
    required this.value,
    required this.onChanged,
  });

  final Strings strings;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<MessageNotificationsTile> createState() =>
      _MessageNotificationsTileState();
}

class _MessageNotificationsTileState extends State<MessageNotificationsTile> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: const ValueKey('message-notifications-toggle'),
        title: Text(widget.strings.messageNotifsTitle),
        value: _value,
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
      ),
    );
  }
}
