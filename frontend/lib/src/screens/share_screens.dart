import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import 'dialog_actions.dart';
import '../models.dart';
import '../platform/share_sheet.dart';

/// Owner settings: send/copy the invite link or code, or revoke. Owners
/// never join other calendars; that is the partner role.
class ShareSettingsSection extends StatefulWidget {
  const ShareSettingsSection({
    super.key,
    required this.api,
    required this.strings,
    required this.user,
    required this.share,
    required this.onShareChanged,
  });

  final ApiClient api;
  final Strings strings;
  final User user;
  final ShareState share;
  final ValueChanged<ShareState> onShareChanged;

  @override
  State<ShareSettingsSection> createState() => _ShareSettingsSectionState();
}

class _ShareSettingsSectionState extends State<ShareSettingsSection> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(widget.strings, err))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Server-provided link; on web an older server without `invite_url` still
  /// gets a working link from this page's own origin.
  String get _inviteLink {
    final share = widget.share;
    if (share.inviteUrl.isNotEmpty) return share.inviteUrl;
    if (kIsWeb && share.inviteCode.isNotEmpty) {
      final code = Uri.encodeQueryComponent(share.inviteCode);
      return '${Uri.base.origin}/?invite=$code';
    }
    return '';
  }

  Future<void> _copy(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(confirmation)));
  }

  /// Android: system share sheet (WhatsApp, SMS…). Elsewhere, copy the link.
  Future<void> _send() async {
    final strings = widget.strings;
    final link = _inviteLink;
    final shared = await shareText(
      strings.shareMessage(code: widget.share.inviteCode, link: link),
      subject: strings.shareSubject,
    );
    if (shared || !mounted) return;
    if (link.isNotEmpty) {
      await _copy(link, strings.linkCopied);
    } else {
      await _copy(widget.share.inviteCode, strings.codeCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isOwner) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = widget.strings;
    final share = widget.share;
    final link = _inviteLink;
    const divider = Divider(height: 1, indent: 16, endIndent: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.shareCalendar.toUpperCase(),
          style: text.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (share.isNone) ...[
                ListTile(
                  title: Text(strings.shareEnable),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.person_add_alt_1, color: scheme.primary),
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            final next = await widget.api.enableShare();
                            widget.onShareChanged(next);
                          }),
                ),
              ] else ...[
                if (share.isOpen) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: FilledButton.icon(
                      key: const ValueKey('share-send-invite'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _send,
                      icon: Icon(canShareNatively ? Icons.share : Icons.link),
                      label: Text(
                        canShareNatively ? strings.shareSend : strings.shareCopyLink,
                      ),
                    ),
                  ),
                  if (link.isNotEmpty)
                    ListTile(
                      key: const ValueKey('share-invite-link'),
                      title: Text(strings.shareInviteLink),
                      subtitle: Text(
                        link,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: strings.shareCopyLink,
                        onPressed: () => _copy(link, strings.linkCopied),
                        icon: const Icon(Icons.link),
                      ),
                    ),
                  ListTile(
                    key: const ValueKey('share-invite-code'),
                    title: Text(strings.shareInviteCode),
                    subtitle: SelectableText(
                      share.inviteCode,
                      style: text.headlineSmall?.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: strings.shareCopyCode,
                      onPressed: share.inviteCode.isEmpty
                          ? null
                          : () => _copy(share.inviteCode, strings.codeCopied),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ),
                  divider,
                ],
                ListTile(
                  title: Text(
                    share.isActive
                        ? '${strings.shareActiveWith} ${share.partnerName.isEmpty ? share.partnerEmail : share.partnerName}'
                        : strings.shareWaiting,
                  ),
                ),
                divider,
                ListTile(
                  title: Text(
                    strings.shareRevoke,
                    style: text.titleMedium?.copyWith(color: scheme.error),
                  ),
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            final next = await widget.api.revokeShare();
                            widget.onShareChanged(next);
                          }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Snackbar text for a failed join: a rejected code vs. anything else.
String joinErrorText(Strings strings, Object err) =>
    err is ApiException && err.statusCode == 400
        ? strings.inviteCodeRejected
        : friendlyError(strings, err);

/// Bright danger red for irreversible account deletion.
const kDeleteAccountColor = Color(0xFFDC2626);

/// Softer orangey-red for logout (okay action, less alarming than delete).
const kLogoutActionColor = Color(0xFFEA580C);

/// Destructive account control — grouped with logout in Settings.
class DeleteAccountSection extends StatefulWidget {
  const DeleteAccountSection({
    super.key,
    required this.api,
    required this.strings,
    required this.onAccountDeleted,
  });

  final ApiClient api;
  final Strings strings;
  final VoidCallback onAccountDeleted;

  @override
  State<DeleteAccountSection> createState() => _DeleteAccountSectionState();
}

class _DeleteAccountSectionState extends State<DeleteAccountSection> {
  bool _busy = false;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.deleteAccount),
        content: Text(widget.strings.deleteAccountWarn),
        actions: [
          DialogActionRow(
            secondary: DialogLinkButton(
              neutral: true,
              onPressed: () => Navigator.pop(context, false),
              label: widget.strings.cancel,
            ),
            primary: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kDeleteAccountColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.deleteAccountConfirm),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteAccount();
      widget.onAccountDeleted();
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
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: kDeleteAccountColor.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(
          widget.strings.deleteAccount,
          style: text.titleMedium?.copyWith(
            color: kDeleteAccountColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: _busy ? null : _confirmDelete,
      ),
    );
  }
}

/// Partner without a calendar yet (or whose access was revoked): join with
/// her code, switch to owner, or delete the account.
class PartnerJoinScreen extends StatefulWidget {
  const PartnerJoinScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.onJoined,
    required this.onAccountDeleted,
    required this.onOpenSettings,
    this.revoked = false,
    this.onSwitchToOwner,
  });

  final ApiClient api;
  final Strings strings;
  final ValueChanged<ShareState> onJoined;
  final VoidCallback onAccountDeleted;
  final VoidCallback onOpenSettings;

  /// Access was revoked (vs. never joined).
  final bool revoked;

  /// Picked the wrong role at first sign-in.
  final VoidCallback? onSwitchToOwner;

  @override
  State<PartnerJoinScreen> createState() => _PartnerJoinScreenState();
}

class _PartnerJoinScreenState extends State<PartnerJoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final share = await widget.api.acceptShare(_code.text.trim());
      widget.onJoined(share);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(joinErrorText(widget.strings, err))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.deleteAccount),
        content: Text(widget.strings.deleteAccountWarn),
        actions: [
          DialogActionRow(
            secondary: DialogLinkButton(
              neutral: true,
              onPressed: () => Navigator.pop(context, false),
              label: widget.strings.cancel,
            ),
            primary: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.deleteAccountConfirm),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteAccount();
      widget.onAccountDeleted();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.brand),
        actions: [
          IconButton(
            tooltip: widget.strings.settings,
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Text(
              widget.revoked
                  ? widget.strings.partnerRevokedTitle
                  : widget.strings.partnerJoinTitle,
              style: text.headlineMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            Text(
              widget.revoked
                  ? widget.strings.partnerRevokedBody
                  : widget.strings.partnerJoinBody,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            TextField(
              key: const ValueKey('partner-join-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: widget.strings.enterInviteCode,
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: Text(widget.strings.joinCalendar),
            ),
            const SizedBox(height: 8),
            if (widget.onSwitchToOwner != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('switch-to-owner'),
                onPressed: _busy ? null : widget.onSwitchToOwner,
                child: Text(widget.strings.switchToOwner),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _delete,
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              child: Text(widget.strings.deleteAccount),
            ),
          ],
      ),
    );
  }
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.api,
    required this.strings,
  });

  final ApiClient api;
  final Strings strings;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  bool _loading = true;
  String? _error;
  List<PartnerNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await widget.api.listInbox();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(widget.strings, err);
      });
    }
  }

  Future<void> _markRead(PartnerNote note) async {
    if (!note.isUnread) return;
    try {
      await widget.api.markInboxNoteRead(note.id);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.inbox)),
      body: _loading
          ? Center(child: Text(widget.strings.loading))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: Text(widget.strings.retry),
                      ),
                    ],
                  ),
                )
              : _notes.isEmpty
                  ? Center(
                      child: Text(
                        widget.strings.inboxEmpty,
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return Material(
                          color: note.isUnread
                              ? scheme.primaryContainer
                              : scheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.4),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _markRead(note),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.fromName.isEmpty
                                        ? note.fromEmail
                                        : note.fromName,
                                    style: text.labelLarge?.copyWith(
                                      color: note.isUnread
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    note.body,
                                    style: text.bodyLarge?.copyWith(
                                      color: note.isUnread
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

Future<void> showPartnerNoteDialog({
  required BuildContext context,
  required ApiClient api,
  required Strings strings,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.leaveNote),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: strings.leaveNote,
          ),
        ),
        actions: [
          DialogActionRow(
            secondary: DialogLinkButton(
              onPressed: () => Navigator.pop(context),
              label: strings.cancel,
            ),
            primary: FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(strings.sendNote),
            ),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (result == null || result.isEmpty) return;
  try {
    await api.createPartnerNote(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noteSent)),
      );
    }
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(strings, err))),
      );
    }
  }
}
