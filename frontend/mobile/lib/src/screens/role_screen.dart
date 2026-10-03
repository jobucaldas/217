import 'package:flutter/material.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';

/// First sign-in: pick owner (takes the pill, fills the calendar) or partner
/// (follows her calendar with an invite).
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({
    super.key,
    required this.api,
    required this.strings,
    required this.onChosen,
    required this.onOpenSettings,
  });

  final ApiClient api;
  final Strings strings;
  final ValueChanged<SessionSnapshot> onChosen;
  final VoidCallback onOpenSettings;

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  bool _busy = false;

  Future<void> _choose(String role) async {
    setState(() => _busy = true);
    try {
      final session = await widget.api.setRole(role);
      widget.onChosen(session);
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text(
            strings.roleChoiceTitle,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 20),
          _RoleCard(
            key: const ValueKey('role-owner'),
            icon: Icons.medication_outlined,
            title: strings.roleOwnerTitle,
            body: strings.roleOwnerBody,
            onTap: _busy ? null : () => _choose('owner'),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            key: const ValueKey('role-partner'),
            icon: Icons.favorite_border,
            title: strings.rolePartnerTitle,
            body: strings.rolePartnerBody,
            onTap: _busy ? null : () => _choose('partner'),
          ),
          const SizedBox(height: 16),
          Text(
            strings.roleChangeLater,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleLarge?.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirms and performs a role switch; returns the new session or null.
Future<SessionSnapshot?> confirmRoleSwitch({
  required BuildContext context,
  required ApiClient api,
  required Strings strings,
  required String role,
}) async {
  final toPartner = role == 'partner';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(toPartner ? strings.switchToPartner : strings.switchToOwner),
      content: toPartner ? Text(strings.switchToPartnerWarn) : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirm-role-switch'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.switchRoleConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    return await api.setRole(role);
  } catch (err) {
    if (context.mounted) {
      final message = err is ApiException && err.statusCode == 409
          ? strings.roleLocked
          : friendlyError(strings, err);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
    return null;
  }
}
