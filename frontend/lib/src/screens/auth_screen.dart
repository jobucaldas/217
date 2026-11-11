import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// Signed-out screen. Driven by the server's auth config: with password
/// sign-in enabled it shows an email+password form (sign in, or create an
/// account when the server allows sign-up); with WorkOS enabled it keeps the
/// existing WorkOS button. Both can be on.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.strings,
    required this.api,
    required this.onSignedIn,
    this.onSignInWorkOS,
    this.onOpenSettings,
    this.server,
    this.onOpenServerSettings,
  });

  final Strings strings;
  final ApiClient api;

  /// Called after a successful email+password sign-in.
  final Future<void> Function(User user) onSignedIn;

  /// The existing WorkOS button flow; null hides it (server without WorkOS).
  final Future<void> Function()? onSignInWorkOS;

  final VoidCallback? onOpenSettings;

  /// Host of the server in use (the built-in one too).
  final String? server;

  /// Opens the server field; null hides it (web always talks to its origin).
  final VoidCallback? onOpenServerSettings;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // false = sign in with an existing account; true = create one.
  bool _create = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  /// Set when the server answered 403 "verify your email to sign in": the
  /// code entry replaces the form until the address is confirmed.
  bool _verify = false;

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool get _passwordOn => widget.api.passwordAuth;
  bool get _signupOn => _passwordOn && widget.api.passwordSignup;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.length < Strings.passwordMinChars) {
      setState(() =>
          _error = widget.strings.passwordTooShort(Strings.passwordMinChars));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_create) {
        await widget.api
            .signUpWithPassword(_email.text.trim(), _password.text);
      }
      final user = await widget.api
          .signInWithPassword(_email.text.trim(), _password.text);
      if (!mounted) return;
      await widget.onSignedIn(user);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        if (err.statusCode == 403 &&
            err.message == 'verify your email to sign in') {
          _verify = true;
        } else {
          _error = switch (err.statusCode) {
            401 => widget.strings.invalidEmailOrPassword,
            409 => widget.strings.emailTaken,
            429 => widget.strings.rateLimited(err.retryAfter ?? 60),
            _ => err.message.isNotEmpty
                ? err.message
                : widget.strings.genericError,
          };
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = widget.strings.connectionError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                  tooltip: widget.strings.settings,
                  onPressed: widget.onOpenSettings,
                  icon: Icon(Icons.settings_outlined, color: scheme.onSurface),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SingleChildScrollView(
                      child: _verify
                          ? _VerifyForm(
                              api: widget.api,
                              strings: widget.strings,
                              email: _email.text.trim(),
                              password: _password.text,
                              onVerified: widget.onSignedIn,
                              onBack: () => setState(() => _verify = false),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wordmark(
                                  widget.strings.brand,
                                  large: true,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  widget.strings.signInSubtitle,
                                  textAlign: TextAlign.center,
                                  style: text.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (_passwordOn) ..._passwordForm(scheme),
                                // The WorkOS button only when the server
                                // really offers AuthKit; without it the
                                // callback is never reachable.
                                if (widget.onSignInWorkOS != null &&
                                    widget.api.workos) ...[
                                  if (_passwordOn) ...[
                                    const SizedBox(height: 16),
                                    _OrDivider(strings: widget.strings),
                                    const SizedBox(height: 16),
                                  ],
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      key: const ValueKey('auth-sign-in'),
                                      onPressed: widget.onSignInWorkOS,
                                      child: Text(_passwordOn
                                          ? widget
                                              .strings.continueWorkOSOther
                                          : widget.strings.continueWorkOS),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              // Kept small at the bottom: it names the server in use and
              // opens the server field, without drawing focus from sign-in.
              if (widget.onOpenServerSettings != null &&
                  widget.server != null &&
                  widget.server!.isNotEmpty)
                Center(
                  child: TextButton(
                    key: const ValueKey('auth-server'),
                    onPressed: widget.onOpenServerSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      widget.strings.serverLabel(widget.server!),
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

  List<Widget> _passwordForm(ColorScheme scheme) {
    final strings = widget.strings;
    return [
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('auth-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              autocorrect: false,
              enableSuggestions: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: strings.emailLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('auth-password'),
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [
                _create ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: strings.passwordLabel,
                helperText: _create ? strings.passwordPolicyHint : null,
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip:
                      _showPassword ? strings.passwordHide : strings.passwordShow,
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          key: const ValueKey('auth-error'),
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _error!,
            style: TextStyle(color: scheme.error),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('auth-submit'),
        onPressed: _busy ? null : _submit,
        child: Text(_create ? strings.createAccount : strings.signInTitle),
      ),
      if (_signupOn)
        TextButton(
          key: ValueKey(_create ? 'auth-to-signin' : 'auth-to-signup'),
          onPressed:
              _busy ? null : () => setState(() => _create = !_create),
          child: Text(
            _create ? strings.signInTitle : strings.createAccount,
          ),
        ),
    ];
  }
}

/// After sign-up on a server with mail (or a login that answered 403 verify):
/// enter the code from the email, ask for a resend (cooldown), or go back.
class _VerifyForm extends StatefulWidget {
  const _VerifyForm({
    required this.api,
    required this.strings,
    required this.email,
    required this.password,
    required this.onVerified,
    required this.onBack,
  });

  final ApiClient api;
  final Strings strings;
  final String email;
  final String password;
  final Future<void> Function(User user) onVerified;
  final VoidCallback onBack;

  @override
  State<_VerifyForm> createState() => _VerifyFormState();
}

class _VerifyFormState extends State<_VerifyForm> {
  bool _busy = false;
  String? _error;
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verifyEmail(widget.email, _code.text.trim());
      final user = await widget.api
          .signInWithPassword(widget.email, widget.password);
      if (!mounted) return;
      await widget.onVerified(user);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.statusCode == 400
          ? widget.strings.invalidCode
          : widget.strings.genericError);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = widget.strings.connectionError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.strings.verifyEmailTitle,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(widget.strings.verifyEmailBody(widget.email)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('verify-code'),
          controller: _code,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: widget.strings.codeLabel),
        ),
        if (_error != null)
          Padding(
            key: const ValueKey('verify-error'),
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('verify-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.strings.verify),
        ),
        _ResendButton(
            api: widget.api, strings: widget.strings, email: widget.email),
        TextButton(
          key: const ValueKey('verify-back'),
          onPressed: _busy ? null : widget.onBack,
          child: Text(widget.strings.cancel),
        ),
      ],
    );
  }
}

/// Resend with a cooldown (the endpoint is rate limited per IP).
class _ResendButton extends StatefulWidget {
  const _ResendButton({
    required this.api,
    required this.strings,
    required this.email,
  });

  final ApiClient api;
  final Strings strings;
  final String email;

  @override
  State<_ResendButton> createState() => _ResendButtonState();
}

class _ResendButtonState extends State<_ResendButton> {
  static const _cooldown = Duration(seconds: 60);
  Timer? _timer;
  int _left = 0;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _left = _cooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _left--;
        if (_left < 0) _left = 0;
      });
      if (_left == 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    if (_left > 0) return;
    try {
      await widget.api.resendVerification(widget.email);
      _startCooldown();
    } catch (_) {
      if (mounted) setState(() => _error = widget.strings.connectionError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        TextButton(
          key: const ValueKey('verify-resend'),
          onPressed: _left > 0 ? null : _resend,
          child: Text(
            _left > 0
                ? widget.strings.resendIn(_left)
                : widget.strings.resendCode,
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: scheme.outline.withValues(alpha: 0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            strings.orDivider,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(child: Divider(color: scheme.outline.withValues(alpha: 0.5))),
      ],
    );
  }
}