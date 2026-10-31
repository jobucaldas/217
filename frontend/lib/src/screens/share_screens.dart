import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
                        canShareNatively
                            ? strings.shareSend
                            : strings.shareCopyLink,
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
    this.onAccountDeleting,
  });

  final ApiClient api;
  final Strings strings;
  final VoidCallback onAccountDeleted;
  final VoidCallback? onAccountDeleting;

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
        content: Text(
            widget.strings.deleteAccountWarn(widget.api.workosUserDeletion)),
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
      widget.onAccountDeleting?.call();
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
    this.onAccountDeleting,
    required this.onOpenSettings,
    this.revoked = false,
    this.onSwitchToOwner,
  });

  final ApiClient api;
  final Strings strings;
  final ValueChanged<ShareState> onJoined;
  final VoidCallback onAccountDeleted;
  final VoidCallback? onAccountDeleting;
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
        content: Text(
            widget.strings.deleteAccountWarn(widget.api.workosUserDeletion)),
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
      widget.onAccountDeleting?.call();
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

/// App bar button that opens the messages screen, with the unread count.
/// Owners and linked partners both have one.
class InboxButton extends StatelessWidget {
  const InboxButton({
    super.key,
    required this.api,
    required this.strings,
    required this.share,
    this.onSynced,
  });

  final ApiClient api;
  final Strings strings;
  final ShareState share;

  /// Called with the messages each time the screen loads them.
  final ValueChanged<List<InboxMessage>>? onSynced;

  @override
  Widget build(BuildContext context) {
    final unread = share.unreadNotes;
    return IconButton(
      key: const ValueKey('inbox-button'),
      tooltip: strings.inbox,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InboxScreen(
              api: api,
              strings: strings,
              canSend: share.isActive,
              onSynced: onSynced,
            ),
          ),
        );
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.forum_outlined),
      ),
    );
  }
}

/// Conversation with the other person of the share: received messages on
/// the left, the user's own on the right, newest at the bottom. Opening it
/// marks what arrived as read.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.api,
    required this.strings,
    this.canSend = false,
    this.onSynced,
  });

  final ApiClient api;
  final Strings strings;

  /// A live share: there is someone to write to.
  final bool canSend;
  final ValueChanged<List<InboxMessage>>? onSynced;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _compose = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<InboxMessage> _messages = const [];

  /// Highlighted for this visit, though already marked read on the server.
  final Set<String> _newIds = {};

  @override
  void initState() {
    super.initState();
    _compose.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _compose.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _messages.isEmpty;
      _error = null;
    });
    try {
      var messages = await widget.api.listInbox();
      final unread = messages.where((m) => m.isUnread).toList();
      if (unread.isNotEmpty) {
        _newIds.addAll(unread.map((m) => m.id));
        await Future.wait(unread
            .map((m) => widget.api.markInboxNoteRead(m.id).catchError((_) {})));
        final now = DateTime.now().toUtc();
        messages = [
          for (final m in messages)
            m.isUnread
                ? InboxMessage(
                    id: m.id,
                    body: m.body,
                    createdAt: m.createdAt,
                    fromName: m.fromName,
                    fromEmail: m.fromEmail,
                    readAt: now,
                  )
                : m,
        ];
      }
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      widget.onSynced?.call(messages);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(widget.strings, err);
      });
    }
  }

  Future<void> _send() async {
    final body = _compose.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.api.sendMessage(body);
      if (!mounted) return;
      _compose.clear();
      setState(() {
        _messages = [sent, ..._messages];
        _sending = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(widget.strings, err))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Widget body;
    if (_loading) {
      body = Center(child: Text(widget.strings.loading));
    } else if (_error != null) {
      body = Center(
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
      );
    } else if (_messages.isEmpty) {
      body = Center(
        child: Text(
          widget.strings.inboxEmpty,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: _messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _MessageBubble(
            message: _messages[index],
            strings: widget.strings,
            highlighted: _newIds.contains(_messages[index].id),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.strings.inbox)),
      body: Column(
        children: [
          Expanded(child: body),
          SafeArea(
            top: false,
            child: widget.canSend
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('message-compose'),
                            controller: _compose,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: widget.strings.messageHint,
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filled(
                          key: const ValueKey('message-send'),
                          tooltip: widget.strings.sendNote,
                          onPressed: _compose.text.trim().isEmpty || _sending
                              ? null
                              : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      widget.strings.messagesNeedPartner,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.strings,
    required this.highlighted,
  });

  final InboxMessage message;
  final Strings strings;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mine = message.fromMe;
    final background = mine
        ? scheme.primary
        : highlighted
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = mine
        ? scheme.onPrimary
        : highlighted
            ? scheme.onPrimaryContainer
            : scheme.onSurface;
    final when = DateFormat.MMMd(strings.dateLocale)
        .add_Hm()
        .format(message.createdAt.toLocal());
    final header = [
      mine ? strings.messageFromMe : message.fromLabel,
      when,
      if (highlighted) strings.messageUnread,
    ].join(' · ');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header,
                  style: text.labelMedium?.copyWith(
                    color: foreground.withValues(alpha: 0.8),
                    fontWeight: highlighted ? FontWeight.w700 : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.body,
                  style: text.bodyLarge?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
