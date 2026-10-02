import 'package:flutter/material.dart';

import '../i18n.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    super.key,
    required this.strings,
    required this.onSignIn,
    required this.onOpenSettings,
    this.showReminderHint = false,
    this.onDismissReminderHint,
    this.customServer,
  });

  final Strings strings;
  final Future<void> Function() onSignIn;
  final VoidCallback onOpenSettings;
  final bool showReminderHint;
  final Future<void> Function()? onDismissReminderHint;

  /// Host of a self-hosted server, shown so sign-in goes where you expect.
  final String? customServer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: const ValueKey('auth-settings'),
                  tooltip: strings.settings,
                  onPressed: onOpenSettings,
                  icon: Icon(Icons.settings_outlined, color: scheme.onSurface),
                ),
              ),
              if (showReminderHint && onDismissReminderHint != null) ...[
                const SizedBox(height: 4),
                Material(
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
                            strings.reminderHint,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onDismissReminderHint,
                          child: Text(strings.reminderHintDismiss),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          strings.brand,
                          textAlign: TextAlign.center,
                          style: text.displayLarge?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          strings.signInSubtitle,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const ValueKey('auth-sign-in'),
                            onPressed: onSignIn,
                            child: Text(strings.continueWorkOS),
                          ),
                        ),
                        if (customServer != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            strings.serverLabel(customServer!),
                            key: const ValueKey('auth-custom-server'),
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
