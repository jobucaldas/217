import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'repeat_minutes_controller.dart';

/// Switch + debounced 1-120 minutes field + helper/error line, shared by the
/// owner daily reminder and partner pill alert "repeat every X minutes" UI.
class RepeatSettingsSection extends StatelessWidget {
  const RepeatSettingsSection({
    super.key,
    required this.toggleKey,
    required this.fieldKey,
    required this.switchTitle,
    required this.switchSubtitle,
    required this.everyLabel,
    required this.minutesUnit,
    required this.helperText,
    required this.repeatEnabled,
    required this.parentEnabled,
    required this.saving,
    required this.controller,
    required this.onToggle,
    required this.onMinutesChanged,
    required this.onMinutesSubmitted,
  });

  final Key toggleKey;
  final Key fieldKey;
  final String switchTitle;
  final String switchSubtitle;
  final String everyLabel;
  final String minutesUnit;

  /// Already formatted with the current saved minutes (e.g. "Repeats every
  /// 15 min..."); shown unless [RepeatMinutesController.error] is set.
  final String helperText;

  /// Whether the repeat is currently turned on.
  final bool repeatEnabled;

  /// Whether the parent reminder/alert this repeat belongs to is enabled;
  /// gates both the switch (together with [saving]) and the minutes field.
  final bool parentEnabled;
  final bool saving;
  final RepeatMinutesController controller;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onMinutesChanged;
  final VoidCallback onMinutesSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasError = controller.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        SwitchListTile(
          key: toggleKey,
          title: Text(switchTitle),
          subtitle: Text(switchSubtitle),
          value: repeatEnabled,
          onChanged: parentEnabled && !saving ? onToggle : null,
        ),
        if (repeatEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(everyLabel),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    key: fieldKey,
                    controller: controller.textController,
                    focusNode: controller.focusNode,
                    // Never gated on `saving`: a save triggered by this
                    // field (or any other control) must not lock out typing.
                    enabled: parentEnabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? scheme.error : scheme.outline,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? scheme.error : scheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onChanged: onMinutesChanged,
                    onSubmitted: (_) => onMinutesSubmitted(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    minutesUnit,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (repeatEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              hasError ? controller.error! : helperText,
              style: text.bodySmall?.copyWith(
                color: hasError ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
