import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../i18n.dart';
import '../models.dart';

/// Owner settings for invite code + revoke, and delete-account control.
class ShareSettingsSection extends StatefulWidget {
  const ShareSettingsSection({
    super.key,
    required this.api,
    required this.strings,
    required this.user,
    required this.share,
    required this.onShareChanged,
    required this.onAccountDeleted,
  });

  final ApiClient api;
  final Strings strings;
  final User user;
  final ShareState share;
  final ValueChanged<ShareState> onShareChanged;
  final VoidCallback onAccountDeleted;

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
        SnackBar(content: Text('$err')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.deleteAccount),
        content: Text(widget.strings.deleteAccountWarn),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.deleteAccountConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.api.deleteAccount();
      widget.onAccountDeleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final share = widget.share;
    final isOwner = widget.user.isOwner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOwner) ...[
          Text(
            widget.strings.shareCalendar.toUpperCase(),
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
                if (share.isNone)
                  ListTile(
                    title: Text(widget.strings.shareEnable),
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
                  )
                else ...[
                  ListTile(
                    title: Text(widget.strings.shareInviteCode),
                    subtitle: Text(
                      share.inviteCode,
                      style: text.headlineSmall?.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: widget.strings.shareCopyCode,
                      onPressed: share.inviteCode.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: share.inviteCode),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(widget.strings.shareCopyCode),
                                ),
                              );
                            },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      share.isActive
                          ? '${widget.strings.shareActiveWith} ${share.partnerName.isEmpty ? share.partnerEmail : share.partnerName}'
                          : widget.strings.shareWaiting,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      widget.strings.shareRevoke,
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
          const SizedBox(height: 20),
        ],
        Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            title: Text(
              widget.strings.deleteAccount,
              style: text.titleMedium?.copyWith(color: scheme.error),
            ),
            onTap: _busy ? null : _confirmDelete,
          ),
        ),
      ],
    );
  }
}

/// Partner reconnect / delete after revoke.
class PartnerRevokedScreen extends StatefulWidget {
  const PartnerRevokedScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.onJoined,
    required this.onAccountDeleted,
    required this.onOpenSettings,
  });

  final ApiClient api;
  final Strings strings;
  final ValueChanged<ShareState> onJoined;
  final VoidCallback onAccountDeleted;
  final VoidCallback onOpenSettings;

  @override
  State<PartnerRevokedScreen> createState() => _PartnerRevokedScreenState();
}

class _PartnerRevokedScreenState extends State<PartnerRevokedScreen> {
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
      final share = await widget.api.acceptShare(_code.text);
      widget.onJoined(share);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err')),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.deleteAccountConfirm),
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
        SnackBar(content: Text('$err')),
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.strings.partnerRevokedTitle,
              style: text.headlineMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            Text(
              widget.strings.partnerRevokedBody,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            TextField(
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
            OutlinedButton(
              onPressed: _busy ? null : _delete,
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              child: Text(widget.strings.deleteAccount),
            ),
          ],
        ),
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
        _error = '$err';
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
              ? Center(child: Text(_error!))
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
  final scheme = Theme.of(context).colorScheme;
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(strings.sendNote),
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
        SnackBar(content: Text(strings.sendNote)),
      );
    }
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$err'),
          backgroundColor: scheme.error,
        ),
      );
    }
  }
}
