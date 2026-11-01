import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    super.key,
    required this.strings,
    required this.onSignIn,
    required this.onOpenSettings,
    this.server,
    this.onOpenServerSettings,
  });

  final Strings strings;
  final Future<void> Function() onSignIn;
  final VoidCallback onOpenSettings;

  /// Host of the server in use (the built-in one too).
  final String? server;

  /// Opens Settings at the server field; null hides the server link
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
                        Wordmark(
                          strings.brand,
                          large: true,
                          textAlign: TextAlign.center,
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
                      ],
                    ),
                  ),
                ),
              ),
              // Kept small at the bottom: it names the server in use and
              // opens the server field, without drawing focus from sign-in.
              if (onOpenServerSettings != null &&
                  server != null &&
                  server!.isNotEmpty)
                Center(
                  child: TextButton(
                    key: const ValueKey('auth-server'),
                    onPressed: onOpenServerSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      strings.serverLabel(server!),
                      textAlign: TextAlign.center,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        decoration: TextDecoration.underline,
                        decorationColor: scheme.onSurfaceVariant,
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
