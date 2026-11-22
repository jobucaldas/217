import 'package:flutter/material.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import 'dialog_actions.dart';

/// Settings › Sign-in methods: set, change or remove the account's
/// email+password credential. Only shown when the server offers password
/// sign-in (`/api/auth/config` → `password`).
class SignInMethodsSection extends StatefulWidget {
  const SignInMethodsSection({
    super.key,
    required this.api,
    required this.strings,
    required this.user,
    required this.group,
    this.onSessionChanged,
  });

  final ApiClient api;
  final Strings strings;
  final User user;

  /// Wraps the rows in the settings group card.
  final Widget Function(List<Widget> children) group;

  /// A set/change/remove answered 204: the session (and has_password) moved.
  final ValueChanged<SessionSnapshot>? onSessionChanged;

  @override
  State<SignInMethodsSection> createState() => _SignInMethodsSectionState();
}

class _SignInMethodsSectionState extends State<SignInMethodsSection> {
  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(ApiException err) {
    if (err.statusCode == 403 && err.message == 'current password is wrong') {
      return widget.strings.currentPasswordWrong;
    }
    if (err.statusCode == 403 && err.message == 'reauth required') {
      return widget.strings.reauthNeeded;
    }
    if (err.statusCode == 409) return widget.strings.removePasswordNeedsOther;
    if (err.message.isNotEmpty) return err.message;
    return friendlyError(widget.strings, err);
  }

  /// Set (no password yet) or change (one exists): asks for the current
  /// password only when the account already has one.
  Future<void> _editPassword() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        api: widget.api,
        strings: widget.strings,
        hasPassword: widget.user.hasPassword,
      ),
    );
    if (saved != true) return;
    // The session's has_password moved; the app follows the fresh snapshot
    // (null when the server cannot be reached right now).
    final session = await _refreshSession();
    if (session != null) widget.onSessionChanged?.call(session);
    if (mounted) _showSnack(widget.strings.passwordSaved);
  }

  Future<void> _removePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.removePasswordTitle),
        content: Text(widget.strings.removePasswordBody),
        actions: [
          DialogActionRow(
            secondary: DialogLinkButton(
              key: const ValueKey('remove-password-cancel'),
              onPressed: () => Navigator.pop(context, false),
              label: widget.strings.cancel,
            ),
            primary: FilledButton(
              key: const ValueKey('remove-password-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.removePassword),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.removePassword();
      final session = await _refreshSession();
      if (session != null) widget.onSessionChanged?.call(session);
      if (mounted) _showSnack(widget.strings.passwordRemoved);
    } on ApiException catch (err) {
      if (mounted) _showSnack(_errorText(err));
    } catch (err) {
      if (mounted) _showSnack(friendlyError(widget.strings, err));
    }
  }

  /// The session after a password change, or null when unreachable.
  Future<SessionSnapshot?> _refreshSession() async {
    try {
      return await widget.api.currentSession();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return widget.group([
      ListTile(
        key: const ValueKey('settings-change-password'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(
          widget.user.hasPassword
              ? widget.strings.changePassword
              : widget.strings.setPassword,
        ),
        trailing:
            Icon(Icons.password_outlined, color: scheme.onSurfaceVariant),
        onTap: _editPassword,
      ),
      if (widget.user.hasPassword)
        ListTile(
          key: const ValueKey('settings-remove-password'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(widget.strings.removePassword),
          trailing: Icon(Icons.remove_circle_outline,
              color: scheme.onSurfaceVariant),
          onTap: _removePassword,
        ),
    ]);
  }
}

/// New password (+ current when changing), with the policy hint and a
/// confirm field; saves through [ApiClient.changePassword].
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.api,
    required this.strings,
    required this.hasPassword,
  });

  final ApiClient api;
  final Strings strings;
  final bool hasPassword;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _errorText(ApiException err) {
    if (err.statusCode == 403 && err.message == 'current password is wrong') {
      return widget.strings.currentPasswordWrong;
    }
    if (err.statusCode == 403 && err.message == 'reauth required') {
      return widget.strings.reauthNeeded;
    }
    if (err.message.isNotEmpty) return err.message;
    return friendlyError(widget.strings, err);
  }

  Future<void> _save() async {
    if (_busy) return;
    final strings = widget.strings;
    if (_next.text.length < Strings.passwordMinChars) {
      setState(
        () => _error = strings.passwordTooShort(Strings.passwordMinChars),
      );
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = strings.passwordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.changePassword(
        currentPassword: widget.hasPassword ? _current.text : '',
        newPassword: _next.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(err);
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(widget.strings, err);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(
        widget.hasPassword ? strings.changePassword : strings.setPassword,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.hasPassword)
            TextField(
              key: const ValueKey('password-current'),
              controller: _current,
              obscureText: true,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration:
                  InputDecoration(labelText: strings.currentPasswordLabel),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('password-new'),
            controller: _next,
            obscureText: true,
            autofocus: !widget.hasPassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.newPasswordLabel,
              helperText: strings.passwordPolicyHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('password-confirm'),
            controller: _confirm,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: strings.confirmPasswordLabel),
          ),
          if (_error != null)
            Padding(
              key: const ValueKey('password-error'),
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        DialogActionRow(
          secondary: DialogLinkButton(
            onPressed: () => Navigator.pop(context, false),
            label: strings.cancel,
          ),
          primary: FilledButton(
            key: const ValueKey('password-save'),
            onPressed: _busy ? null : _save,
            child: Text(strings.save),
          ),
        ),
      ],
    );
  }
}
