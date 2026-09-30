import 'package:flutter/material.dart';

import '../i18n.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    super.key,
    required this.strings,
    required this.apiBaseUrl,
    required this.onSignIn,
    required this.onToggleLanguage,
    required this.onOpenSettings,
  });

  final Strings strings;
  final String apiBaseUrl;
  final Future<void> Function() onSignIn;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: strings.settings,
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onToggleLanguage,
                      child: Text(strings.pt ? 'English' : 'Português'),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  strings.brand,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.signInSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  apiBaseUrl,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: onSignIn,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(strings.continueWorkOS),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
