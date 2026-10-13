import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import '../platform/save_data.dart';

/// The server people are on, as shown in the privacy notice.
String serverLabel(ApiClient api) {
  final base = api.config.apiBaseUrl;
  final authority =
      base.isEmpty ? Uri.base.authority : Uri.tryParse(base)?.authority;
  return (authority == null || authority.isEmpty) ? '217' : authority;
}

/// What is processed, why, where, and the user's rights (LGPD arts. 9, 11, 18).
class PrivacyNoticeBody extends StatelessWidget {
  const PrivacyNoticeBody({
    super.key,
    required this.strings,
    required this.server,
    this.contact,
  });

  final Strings strings;
  final String server;
  final String? contact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Highlighted, as LGPD art. 11 asks of consent for sensitive data.
        Container(
          key: const ValueKey('privacy-sensitive'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.privacySensitiveTitle,
                      style: text.titleMedium
                          ?.copyWith(color: scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                strings.privacySensitiveBody,
                style: text.bodyMedium
                    ?.copyWith(color: scheme.onTertiaryContainer),
              ),
            ],
          ),
        ),
        section(strings.privacyWhatTitle, strings.privacyWhatBody),
        section(strings.privacyWhyTitle, strings.privacyWhyBody),
        section(strings.privacyWhereTitle, strings.privacyWhereBody(server)),
        section(strings.privacyRightsTitle, strings.privacyRightsBody),
        section(
            strings.privacyContactTitle, strings.privacyContactBody(contact)),
      ],
    );
  }
}

/// After sign-in, until the user agrees to the current privacy notice: the
/// server refuses to process their data before that.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.version,
    required this.onAccepted,
    required this.onDecline,
    required this.onOpenSettings,
  });

  final ApiClient api;
  final Strings strings;
  final int version;
  final ValueChanged<SessionSnapshot> onAccepted;
  final VoidCallback onDecline;
  final VoidCallback onOpenSettings;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  bool _busy = false;
  String? _contact;

  @override
  void initState() {
    super.initState();
    widget.api.privacyContact().then((contact) {
      if (mounted) setState(() => _contact = contact);
    });
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      widget.onAccepted(await widget.api.acceptConsent(widget.version));
    } catch (err) {
      if (!mounted) return;
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
      appBar: AppBar(
        title: Text(strings.brand),
        actions: [
          IconButton(
            tooltip: strings.settings,
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            strings.privacyTitle,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 16),
          PrivacyNoticeBody(
            strings: strings,
            server: serverLabel(widget.api),
            contact: _contact,
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            key: const ValueKey('consent-checkbox'),
            value: _agreed,
            onChanged:
                _busy ? null : (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              strings.consentCheckbox,
              style: text.bodyLarge?.copyWith(color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('consent-accept'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _agreed && !_busy ? _accept : null,
            child: Text(strings.consentAccept),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('consent-decline'),
            onPressed: _busy ? null : widget.onDecline,
            child: Text(strings.consentDecline),
          ),
        ],
      ),
    );
  }
}

/// The privacy notice on its own page (Settings).
class PrivacyNoticePage extends StatefulWidget {
  const PrivacyNoticePage(
      {super.key, required this.api, required this.strings});

  final ApiClient api;
  final Strings strings;

  @override
  State<PrivacyNoticePage> createState() => _PrivacyNoticePageState();
}

class _PrivacyNoticePageState extends State<PrivacyNoticePage> {
  String? _contact;

  @override
  void initState() {
    super.initState();
    widget.api.privacyContact().then((contact) {
      if (mounted) setState(() => _contact = contact);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.privacyNotice)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PrivacyNoticeBody(
            strings: widget.strings,
            server: serverLabel(widget.api),
            contact: _contact,
          ),
        ],
      ),
    );
  }
}

/// Settings row that downloads everything the server holds about the user.
class DownloadDataTile extends StatefulWidget {
  const DownloadDataTile({
    super.key,
    required this.api,
    required this.strings,
    this.save = saveDataFile,
  });

  final ApiClient api;
  final Strings strings;

  /// Hands the file to the user; injectable for tests.
  final Future<SaveDataOutcome> Function(String name, String content) save;

  @override
  State<DownloadDataTile> createState() => _DownloadDataTileState();
}

class _DownloadDataTileState extends State<DownloadDataTile> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    final strings = widget.strings;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await widget.api.exportData();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final outcome = await widget.save('217-data-$today.json', json);
      final String? message;
      switch (outcome.how) {
        case SaveDataHow.downloaded:
          message = strings.dataDownloaded;
        case SaveDataHow.saved:
          message = strings.dataSavedTo(outcome.path ?? '');
        case SaveDataHow.shared:
          message = null;
        case SaveDataHow.unsupported:
          await Clipboard.setData(ClipboardData(text: json));
          message = strings.dataCopied;
      }
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (err) {
      if (kDebugMode) debugPrint('export failed: $err');
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(strings, err))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: const ValueKey('download-data'),
      leading: Icon(Icons.download_outlined, color: scheme.primary),
      title: Text(widget.strings.downloadData),
      subtitle: Text(widget.strings.downloadDataBlurb),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busy ? null : _download,
    );
  }
}
