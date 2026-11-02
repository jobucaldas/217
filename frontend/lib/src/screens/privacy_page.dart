import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../config.dart';
import '../i18n.dart';
import '../models.dart';
import '../platform/open_url.dart';
import '../platform/web_page.dart';
import '../privacy_text.dart';
import '../theme/app_theme.dart';
import 'dialog_actions.dart';
import 'share_screens.dart' show kDeleteAccountColor;

/// What the privacy pages can do for the account signed in to this browser.
enum PrivacyAction { download, withdraw, delete }

extension on PrivacyAction {
  String get id => name;
}

PrivacyAction? privacyActionFrom(String? raw) {
  for (final action in PrivacyAction.values) {
    if (action.id == raw) return action;
  }
  return null;
}

/// The web-only part of the privacy pages: the browser's session and what
/// the app does after an action.
class PrivacyWebSession {
  const PrivacyWebSession({
    required this.user,
    required this.consentRequired,
    required this.recentSignIn,
    required this.onSignIn,
    required this.onSessionChanged,
    required this.onDeleted,
    this.initialAction,
  });

  final User? user;
  final bool consentRequired;

  /// Signed in within the last few minutes (the server says so).
  final bool recentSignIn;

  /// Signs in through AuthKit and comes back to [returnTo].
  final Future<void> Function(String returnTo) onSignIn;

  /// Consent was withdrawn: the app takes the new session.
  final ValueChanged<SessionSnapshot> onSessionChanged;

  /// The account is gone: the app forgets it.
  final VoidCallback onDeleted;

  /// The warning to open first (`?confirm=`, after signing in again).
  final PrivacyAction? initialAction;
}

/// The privacy notice ([WebPage.privacy]) or the account deletion page
/// ([WebPage.deleteAccount]). On web ([web] set) the signed-in browser
/// downloads, withdraws or deletes here, after a warning and a recent
/// sign-in; in the apps the same page links to its web version for that.
class PrivacyPage extends StatefulWidget {
  const PrivacyPage({
    super.key,
    required this.api,
    required this.strings,
    this.page = WebPage.privacy,
    this.web,
    this.onLanguageChanged,
    this.onOpenApp,
    this.onBrowserOpened,
    this.openUrl = openExternalUrl,
    this.download = saveDownload,
  });

  final ApiClient api;
  final Strings strings;
  final WebPage page;
  final PrivacyWebSession? web;
  final ValueChanged<AppLanguage>? onLanguageChanged;

  /// Standalone web page: back to the app.
  final VoidCallback? onOpenApp;

  /// Apps: the web page was opened in the browser.
  final VoidCallback? onBrowserOpened;

  final Future<bool> Function(String url) openUrl;
  final bool Function(String fileName, List<int> bytes, String mimeType)
      download;

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  bool _busy = false;
  String? _notice;
  String? _error;
  bool _deleted = false;

  PrivacyText get _t => PrivacyText(widget.strings.language);
  Strings get _s => widget.strings;
  bool get _deletePage => widget.page == WebPage.deleteAccount;

  @override
  void initState() {
    super.initState();
    final action = widget.web?.initialAction;
    if (action != null && widget.web?.user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start(action);
      });
    }
  }

  /// This page's own path, in the current language, with [action]'s warning
  /// open when given (where a fresh sign-in comes back to).
  String _pagePath([PrivacyAction? action]) {
    final path = _deletePage ? accountDeletePagePath : privacyPagePath;
    return Uri(path: path, queryParameters: {
      'lang': _s.language.id,
      if (action != null) 'confirm': action.id,
    }).toString();
  }

  String get _server {
    if (kIsWeb) return Uri.base.host.isEmpty ? '217' : Uri.base.host;
    final authority = Uri.tryParse(widget.api.config.apiBaseUrl)?.authority;
    return authority == null || authority.isEmpty ? '217' : authority;
  }

  Future<void> _open(String url) async {
    if (await widget.openUrl(url)) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_s.linkCopied)));
  }

  Future<void> _openInBrowser() async {
    widget.onBrowserOpened?.call();
    await _open(widget.api.privacyPageUrl(
      _s.language.id,
      deleteAccount: _deletePage,
    ));
  }

  Future<void> _signIn([PrivacyAction? action]) async {
    final web = widget.web;
    if (web == null) return;
    setState(() => _error = null);
    try {
      await web.onSignIn(_pagePath(action));
    } catch (_) {
      if (mounted) setState(() => _error = _t.signInFailed);
    }
  }

  /// Whether the browser signed in recently, asking the server again (the
  /// page may have stayed open for a while).
  Future<bool> _recentSignIn() async {
    try {
      final session = await widget.api.currentSession();
      return session.user != null && session.recentSignIn;
    } catch (_) {
      return widget.web?.recentSignIn ?? false;
    }
  }

  Future<void> _start(PrivacyAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final fresh = await _recentSignIn();
    if (!mounted) return;
    setState(() => _busy = false);
    final confirmed = await _confirm(action, fresh: fresh);
    if (!mounted || confirmed != true) return;
    if (!fresh) {
      await _signIn(action);
      return;
    }
    await _run(action);
  }

  Future<bool?> _confirm(PrivacyAction action, {required bool fresh}) {
    final danger = action != PrivacyAction.download;
    final (title, warn, label) = switch (action) {
      PrivacyAction.download => (
          _t.downloadConfirmTitle,
          _t.downloadWarn,
          _t.downloadConfirm
        ),
      PrivacyAction.withdraw => (
          _t.withdrawConfirmTitle,
          _t.withdrawWarn,
          _t.withdrawTitle
        ),
      PrivacyAction.delete => (
          _t.deleteConfirmTitle,
          _t.deleteWarn(widget.api.workosUserDeletion),
          _t.deleteConfirm
        ),
    };
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('privacy-confirm-${action.id}'),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warn),
            if (!fresh) ...[
              const SizedBox(height: 12),
              Text(
                _t.reauthNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          // Irreversible steps keep Cancel as the prominent button, like
          // Settings' delete account.
          if (danger)
            DialogActionRow(
              secondary: DialogLinkButton(
                key: const ValueKey('privacy-confirm'),
                onPressed: () => Navigator.pop(context, true),
                label: fresh ? label : _t.reauthAction,
              ),
              primary: FilledButton(
                key: const ValueKey('privacy-cancel'),
                style: FilledButton.styleFrom(
                  backgroundColor: kDeleteAccountColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, false),
                child: Text(_s.cancel),
              ),
            )
          else
            DialogActionRow(
              secondary: DialogLinkButton(
                key: const ValueKey('privacy-cancel'),
                onPressed: () => Navigator.pop(context, false),
                label: _s.cancel,
              ),
              primary: FilledButton(
                key: const ValueKey('privacy-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(fresh ? label : _t.reauthAction),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _run(PrivacyAction action) async {
    final web = widget.web;
    if (web == null) return;
    setState(() => _busy = true);
    try {
      switch (action) {
        case PrivacyAction.download:
          final file = await widget.api.exportAccount();
          widget.download(file.fileName, file.bytes, 'application/json');
        case PrivacyAction.withdraw:
          final session = await widget.api.withdrawConsent();
          web.onSessionChanged(session);
          if (mounted) setState(() => _notice = _t.doneWithdrawn);
        case PrivacyAction.delete:
          await widget.api.deleteAccount();
          web.onDeleted();
          if (mounted) {
            setState(() {
              _deleted = true;
              _notice = _t.doneDeleted;
            });
          }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = switch (action) {
            PrivacyAction.download => _t.downloadFailed,
            PrivacyAction.withdraw => _t.withdrawFailed,
            PrivacyAction.delete => _t.deleteFailed,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final t = _t;
    return Scaffold(
      appBar: AppBar(
        title: Wordmark(_s.brand),
        actions: [
          if (widget.onLanguageChanged != null)
            PopupMenuButton<AppLanguage>(
              key: const ValueKey('privacy-language'),
              tooltip: _s.languageLabel,
              icon: const Icon(Icons.translate),
              initialValue: _s.language,
              onSelected: widget.onLanguageChanged,
              itemBuilder: (_) => [
                for (final language in AppLanguage.values)
                  PopupMenuItem(
                    value: language,
                    child: Text(language.nativeName),
                  ),
              ],
            ),
          if (widget.onOpenApp != null)
            TextButton(
              key: const ValueKey('privacy-open-app'),
              onPressed: widget.onOpenApp,
              child: Text(t.openApp),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: [
                Text(
                  _deletePage ? t.deletePageTitle : t.title,
                  style: text.headlineMedium?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  _deletePage ? t.deletePageIntro : t.intro,
                  style:
                      text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (_notice != null)
                  _Banner(
                    key: const ValueKey('privacy-notice-banner'),
                    text: _notice!,
                    color: scheme.primary,
                    icon: Icons.check_circle_outline,
                  ),
                if (_error != null)
                  _Banner(
                    key: const ValueKey('privacy-error-banner'),
                    text: _error!,
                    color: scheme.error,
                    icon: Icons.error_outline,
                  ),
                if (_deletePage)
                  ..._deleteSections(context)
                else
                  ..._noticeSections(context),
                const SizedBox(height: 28),
                _SectionTitle(t.yourDataTitle),
                ..._dataSection(context),
                if (_deletePage) ...[
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('privacy-full-notice'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () => kIsWeb
                          ? goToWebPath(Uri(
                              path: privacyPagePath,
                              queryParameters: {'lang': _s.language.id},
                            ).toString())
                          : Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PrivacyPage(
                                api: widget.api,
                                strings: widget.strings,
                                onBrowserOpened: widget.onBrowserOpened,
                                openUrl: widget.openUrl,
                              ),
                            )),
                      child: Text(t.privacyNoticeLink),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _noticeSections(BuildContext context) {
    final t = _t;
    return [
      _HighlightCard(title: t.sensitiveTitle, body: t.sensitiveBody),
      _Section(title: t.whatTitle, body: t.whatBody),
      _Section(title: t.whyTitle, body: t.whyBody),
      _Section(title: t.whereTitle, body: t.whereBody(_server)),
      _Section(title: t.rightsTitle, body: t.rightsBody),
      const SizedBox(height: 24),
      _SectionTitle(t.contactTitle),
      _contact(context, t.contactNone),
    ];
  }

  List<Widget> _deleteSections(BuildContext context) {
    final t = _t;
    final contact = widget.api.privacyContact;
    final steps = [
      t.deleteStepApp,
      t.deleteStepWeb,
      contact.isEmpty ? t.deleteStepNoContact : t.deleteStepContact(contact),
    ];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 20),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.deleteStepsTitle,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Text('${i + 1}', style: text.labelLarge),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(steps[i], style: text.bodyLarge),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      _Section(title: t.deletedDataTitle, body: t.deletedDataBody),
      _Section(
        title: t.keptDataTitle,
        body: t.keptDataBody(widget.api.workosUserDeletion),
      ),
    ];
  }

  /// PRIVACY_CONTACT as a link (mailto: for an email), else plain text.
  Widget _contact(BuildContext context, String fallback) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final contact = widget.api.privacyContact;
    final uri = Uri.tryParse(contact);
    String? link;
    if (contact.contains('@') && !contact.contains('://')) {
      link = 'mailto:$contact';
    } else if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      link = contact;
    }
    if (link == null) {
      return Text(
        contact.isEmpty ? fallback : contact,
        style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final target = link;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const ValueKey('privacy-contact'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        onPressed: () => _open(target),
        child: Text(
          contact,
          style: text.bodyLarge?.copyWith(
            color: scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.primary,
          ),
        ),
      ),
    );
  }

  List<Widget> _dataSection(BuildContext context) {
    final t = _t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant);
    final web = widget.web;
    if (web == null) {
      return [
        Text(t.manageInBrowserBody, style: muted),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('privacy-open-browser'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _openInBrowser,
          icon: const Icon(Icons.open_in_new),
          label: Text(t.manageInBrowserAction),
        ),
      ];
    }
    final user = web.user;
    if (user == null || _deleted) {
      if (_deleted) return const [];
      if (!widget.api.authkit) return [Text(t.signInUnavailable, style: muted)];
      return [
        Text(t.signInPrompt, style: muted),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('privacy-sign-in'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : () => _signIn(),
          child: Text(t.signInAction),
        ),
      ];
    }
    return [
      Text(
        web.consentRequired
            ? '${t.signedInAs(user.email)} ${t.noConsent}'
            : t.signedInAs(user.email),
        style: muted,
      ),
      if (!_deletePage)
        _ActionCard(
          key: const ValueKey('privacy-download'),
          title: t.downloadTitle,
          body: t.downloadBody,
          label: t.downloadTitle,
          style: _ActionStyle.primary,
          onPressed: _busy ? null : () => _start(PrivacyAction.download),
        ),
      if (!_deletePage && !web.consentRequired)
        _ActionCard(
          key: const ValueKey('privacy-withdraw'),
          title: t.withdrawTitle,
          body: t.withdrawBody,
          label: t.withdrawTitle,
          style: _ActionStyle.outlined,
          onPressed: _busy ? null : () => _start(PrivacyAction.withdraw),
        ),
      _ActionCard(
        key: const ValueKey('privacy-delete'),
        title: t.deleteTitle,
        body: t.deleteBody,
        label: t.deleteTitle,
        style: _ActionStyle.danger,
        onPressed: _busy ? null : () => _start(PrivacyAction.delete),
      ),
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          Text(
            body,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style:
                    text.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ActionStyle { primary, outlined, danger }

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.title,
    required this.body,
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String label;
  final _ActionStyle style;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const size = Size.fromHeight(48);
    final button = switch (style) {
      _ActionStyle.primary => FilledButton(
          style: FilledButton.styleFrom(minimumSize: size),
          onPressed: onPressed,
          child: Text(label),
        ),
      _ActionStyle.outlined => OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: size),
          onPressed: onPressed,
          child: Text(label),
        ),
      _ActionStyle.danger => OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: size,
            foregroundColor: kDeleteAccountColor,
            side: BorderSide(
              color: kDeleteAccountColor.withValues(alpha: 0.6),
            ),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        shape: style == _ActionStyle.danger
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: kDeleteAccountColor.withValues(alpha: 0.45),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              button,
            ],
          ),
        ),
      ),
    );
  }
}
