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
    this.onOpenServerSettings,
    this.onOpenSelfHostGuide,
    this.onDismissSelfHostCard,
  });

  final Strings strings;
  final Future<void> Function() onSignIn;
  final VoidCallback onOpenSettings;
  final bool showReminderHint;
  final Future<void> Function()? onDismissReminderHint;

  /// Host of a self-hosted server, shown so sign-in goes where you expect.
  final String? customServer;

  /// Opens Settings at the self-hosted server field; null hides the tip
  /// (web always talks to the server that serves it).
  final VoidCallback? onOpenServerSettings;

  /// Dismissible "run your own server" card (web): shown when both are set.
  final VoidCallback? onOpenSelfHostGuide;
  final VoidCallback? onDismissSelfHostCard;

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
                        if (onOpenServerSettings != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: onOpenServerSettings,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                            ),
                            child: Text(
                              customServer != null
                                  ? strings.serverLabel(customServer!)
                                  : strings.selfHostTip,
                              key: ValueKey(
                                customServer != null
                                    ? 'auth-custom-server'
                                    : 'auth-self-host-tip',
                              ),
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                decoration: TextDecoration.underline,
                                decorationColor: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (onOpenSelfHostGuide != null && onDismissSelfHostCard != null)
                Material(
                  key: const ValueKey('auth-self-host-card'),
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.dns_outlined,
                            color: scheme.onSecondaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  strings.selfHostCard,
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey('auth-self-host-guide'),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.onSecondaryContainer,
                                  padding: EdgeInsets.zero,
                                  textStyle: text.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                onPressed: onOpenSelfHostGuide,
                                child: Text(strings.selfHostGuide),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('auth-self-host-dismiss'),
                          tooltip: strings.dismiss,
                          onPressed: onDismissSelfHostCard,
                          icon: Icon(
                            Icons.close,
                            size: 20,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ],
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
