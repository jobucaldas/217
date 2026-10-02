import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n.dart';

/// Asks for the 217 server to use. Builds without a built-in server (release
/// APKs) show it on first launch; signed out, it also changes the server.
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.onConnected,
    required this.onOpenGuide,
    this.onOpenSettings,
    this.changing = false,
    this.requireHttps = kReleaseMode,
  });

  final ApiClient api;
  final Strings strings;

  /// The server was checked and saved. [changed] is false when it was the
  /// one already in use; [inviteCode] comes from a pasted invite link.
  final void Function({required bool changed, String? inviteCode}) onConnected;
  final VoidCallback onOpenGuide;

  /// Settings gear (language, theme) on the first-launch screen.
  final VoidCallback? onOpenSettings;

  /// Pushed from the sign-in screen to switch servers (back arrow, prefilled).
  final bool changing;

  /// Release builds can't use cleartext http:// (see the release manifest).
  final bool requireHttps;

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  late final TextEditingController _address = TextEditingController(
    text: widget.changing ? widget.api.config.apiBaseUrl : '',
  );
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_checking) return;
    final strings = widget.strings;
    final String base;
    try {
      base = ApiClient.parseApiBase(_address.text);
    } on FormatException {
      setState(() => _error = strings.serverAddressInvalid);
      return;
    }
    if (base.isEmpty) {
      setState(() => _error = strings.serverAddressInvalid);
      return;
    }
    if (widget.requireHttps && Uri.parse(base).scheme != 'https') {
      setState(() => _error = strings.serverNeedsHttps);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final check = await widget.api.checkServer(baseUrl: base);
    if (!mounted) return;
    if (check != ServerCheck.ok) {
      setState(() {
        _checking = false;
        _error = switch (check) {
          ServerCheck.unreachable => strings.serverUnreachable,
          ServerCheck.notA217Server => strings.connectionFail,
          ServerCheck.signInNotConfigured => strings.serverSignInOff,
          ServerCheck.ok => null,
        };
      });
      return;
    }
    final changed = await widget.api.setApiBaseUrl(base);
    if (!mounted) return;
    setState(() => _checking = false);
    widget.onConnected(
      changed: changed,
      inviteCode: ApiClient.inviteCodeIn(_address.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = widget.strings;

    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.changing) ...[
          Text(
            strings.serverSetupTitle,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            strings.serverSetupIntro,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          strings.serverSetupBody,
          textAlign: widget.changing ? TextAlign.start : TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('server-setup-address'),
          controller: _address,
          enabled: !_checking,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: text.bodyLarge?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            labelText: strings.serverAddress,
            hintText: strings.serverAddressHint,
            prefixIcon: const Icon(Icons.dns_outlined),
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('server-setup-connect'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _checking ? null : _connect,
          child: _checking
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Text(strings.connect),
        ),
        if (widget.changing) ...[
          const SizedBox(height: 12),
          Text(
            strings.changeServerNote,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: widget.changing ? Alignment.centerLeft : Alignment.center,
          child: TextButton.icon(
            key: const ValueKey('server-setup-guide'),
            onPressed: widget.onOpenGuide,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(strings.selfHostGuide),
          ),
        ),
      ],
    );

    if (widget.changing) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.changeServerTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [form],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.onOpenSettings != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const ValueKey('server-setup-settings'),
                    tooltip: strings.settings,
                    onPressed: widget.onOpenSettings,
                    icon: Icon(Icons.settings_outlined, color: scheme.onSurface),
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.brand,
                          textAlign: TextAlign.center,
                          style: text.displayLarge?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 28),
                        form,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
