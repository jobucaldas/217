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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: 0.72),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
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
                  style: text.displayLarge?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  strings.signInSubtitle,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: onSignIn,
                  child: Text(strings.continueWorkOS),
                ),
                const SizedBox(height: 16),
                Text(
                  apiBaseUrl,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
