import 'package:flutter/material.dart';

import '../i18n.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    super.key,
    required this.strings,
    required this.onSignIn,
    required this.onOpenSettings,
    this.customServer,
    this.onOpenServerSettings,
  });

  final Strings strings;
  final Future<void> Function() onSignIn;
  final VoidCallback onOpenSettings;

  /// Host of a self-hosted server, shown so sign-in goes where you expect.
  final String? customServer;

  /// Opens Settings at the self-hosted server field; null hides the tip
  /// (web always talks to the server that serves it).
  final VoidCallback? onOpenServerSettings;

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
            ],
          ),
        ),
      ),
    );
  }
}
