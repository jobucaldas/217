import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../config.dart';
import '../errors.dart';
import '../i18n.dart';
import '../theme/app_theme.dart';
import '../models.dart';
import '../platform/open_url.dart';
import '../platform/web_page.dart';
import 'privacy_page.dart';

/// Opens the privacy notice. On web that is the app's own page
/// (`/app/privacy`, where the signed-in browser also downloads, withdraws and
/// deletes); in the apps it opens in-app, linking to that web page for those
/// actions ([onBrowserOpened] runs when it does).
Future<void> openPrivacyNotice(
  BuildContext context,
  ApiClient api,
  Strings strings, {
  Future<bool> Function(String url) open = openExternalUrl,
  VoidCallback? onBrowserOpened,
}) async {
  if (kIsWeb) {
    goToWebPath(Uri(
      path: privacyPagePath,
      queryParameters: {'lang': strings.language.id},
    ).toString());
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PrivacyPage(
      api: api,
      strings: strings,
      openUrl: open,
      onBrowserOpened: onBrowserOpened,
    ),
  ));
}

/// After sign-in, until the user agrees to the current privacy notice: the
/// server refuses to process their data before that. The notice itself is
/// its own page; here there is only its link, accept and cancel.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.version,
    required this.onAccepted,
    this.onNoticeChanged,
    required this.onDecline,
    this.onNoticeOpened,
    this.openUrl = openExternalUrl,
  });

  final ApiClient api;
  final Strings strings;
  final int version;
  final ValueChanged<SessionSnapshot> onAccepted;
  final Future<void> Function(int version)? onNoticeChanged;

  /// Cancel: back to before this screen (signs out to the sign-in screen).
  final VoidCallback onDecline;

  /// Called when the notice's web page is opened in the browser (the app
  /// re-reads the session on return, since the account may be deleted there).
  final VoidCallback? onNoticeOpened;

  /// Opens the notice link; injectable for tests.
  final Future<bool> Function(String url) openUrl;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      widget.onAccepted(await widget.api.acceptConsent(widget.version));
    } catch (err) {
      if (!mounted) return;
      if (err is ApiException &&
          err.statusCode == 409 &&
          err.consentVersion != null) {
        // The notice changed meanwhile: take the new version, and ask again.
        await widget.onNoticeChanged?.call(err.consentVersion!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.strings.consentNoticeChanged)),
          );
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(widget.strings, err))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(title: Wordmark(strings.brand)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              strings.privacyTitle,
              style: text.headlineMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            Text(
              strings.consentIntro,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const ValueKey('consent-notice-link'),
                leading:
                    Icon(Icons.privacy_tip_outlined, color: scheme.primary),
                title: Text(strings.privacyNotice),
                trailing:
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: () => openPrivacyNotice(
                  context,
                  widget.api,
                  strings,
                  open: widget.openUrl,
                  onBrowserOpened: widget.onNoticeOpened,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('consent-accept'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _accept,
              child: Text(strings.consentAccept),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('consent-decline'),
              style:
                  TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : widget.onDecline,
              child: Text(strings.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
