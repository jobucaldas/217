import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../dates.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import '../stage_suggestion.dart';

/// Settings › Personal: display name (both roles), birth month and
/// reproductive stage (owner), and the owner's pending stage suggestion.
class PersonalSection extends StatefulWidget {
  const PersonalSection({
    super.key,
    required this.api,
    required this.strings,
    required this.user,
    required this.group,
    this.suggestion,
    this.showUpdated = false,
    this.onStageChanged,
    this.onProfileChanged,
  });

  final ApiClient api;
  final Strings strings;
  final User user;

  /// Wraps the rows in the settings group card.
  final Widget Function(List<Widget> children) group;
  final StageSuggestion? suggestion;

  /// Start with the "updated" notice (a suggestion was accepted elsewhere).
  final bool showUpdated;
  final ValueChanged<SessionSnapshot>? onStageChanged;
  final ValueChanged<SessionSnapshot>? onProfileChanged;

  /// How long the "updated" notice stays.
  static const updatedNoticeDuration = Duration(seconds: 2);

  @override
  State<PersonalSection> createState() => _PersonalSectionState();
}

class _PersonalSectionState extends State<PersonalSection> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user.shownName);
  bool _savingName = false;
  bool _savingBirth = false;
  bool _savingStage = false;
  int _stageResets = 0;
  bool _updated = false;
  Timer? _updatedTimer;

  @override
  void initState() {
    super.initState();
    if (widget.showUpdated) _flashUpdated();
  }

  @override
  void didUpdateWidget(covariant PersonalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep what is being typed; follow the server otherwise.
    if (oldWidget.user.shownName != widget.user.shownName &&
        _name.text.trim() == oldWidget.user.shownName) {
      _name.text = widget.user.shownName;
    }
  }

  @override
  void dispose() {
    _updatedTimer?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _flashUpdated() {
    _updatedTimer?.cancel();
    _updated = true;
    _updatedTimer = Timer(PersonalSection.updatedNoticeDuration, () {
      if (mounted) setState(() => _updated = false);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _nameChanged => _name.text.trim() != widget.user.shownName;

  Future<void> _saveName() async {
    if (!_nameChanged || _savingName) return;
    setState(() => _savingName = true);
    try {
      // Clearing the field (or typing the sign-in name) drops the override.
      final typed = _name.text.trim();
      final session = await widget.api
          .updateProfile(displayName: typed == widget.user.name ? '' : typed);
      if (!mounted) return;
      _name.text = session.user?.shownName ?? typed;
      setState(() => _savingName = false);
      widget.onProfileChanged?.call(session);
      _showSnack(widget.strings.displayNameSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingName = false);
      _showSnack(friendlyError(widget.strings, error));
    }
  }

  Future<void> _saveBirth(String value) async {
    setState(() => _savingBirth = true);
    try {
      final session = await widget.api.updateProfile(birthDate: value);
      if (!mounted) return;
      setState(() => _savingBirth = false);
      // The birth month feeds the stage suggestion, so refresh the cycle.
      widget.onStageChanged?.call(session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingBirth = false);
      _showSnack(friendlyError(widget.strings, error));
    }
  }

  Future<void> _saveStage(String stage, {bool fromSuggestion = false}) async {
    setState(() => _savingStage = true);
    try {
      final session = await widget.api.setStage(stage);
      if (!mounted) return;
      setState(() {
        _savingStage = false;
        if (fromSuggestion) _flashUpdated();
      });
      if (fromSuggestion) widget.suggestion?.clear();
      widget.onStageChanged?.call(session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _savingStage = false;
          _stageResets++;
        });
        _showSnack(friendlyError(widget.strings, error));
      }
    }
  }

  DateTime? get _birth => parseBirthMonth(widget.user.birthDate);

  Future<void> _pickBirth() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _BirthMonthDialog(strings: widget.strings, initial: _birth),
    );
    if (result == null || result == widget.user.birthDate) return;
    await _saveBirth(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = widget.strings;
    final user = widget.user;
    final birth = _birth;
    final hint = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: ListenableBuilder(
          listenable: _name,
          builder: (context, _) => TextField(
            key: const ValueKey('display-name'),
            controller: _name,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _saveName(),
            style: text.bodyLarge?.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: strings.displayName,
              counterText: '',
              suffixIcon: _nameChanged
                  ? IconButton(
                      key: const ValueKey('display-name-save'),
                      tooltip: strings.save,
                      onPressed: _savingName ? null : _saveName,
                      icon: const Icon(Icons.check_rounded),
                    )
                  : null,
            ),
          ),
        ),
      ),
      if (user.isOwner) ...[
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          key: const ValueKey('birth-date'),
          enabled: !_savingBirth,
          title: Text(strings.birthDate),
          subtitle: Text(
            birth == null ? strings.notSet : strings.dates.monthYear(birth),
          ),
          trailing: Icon(Icons.edit_calendar_outlined,
              color: scheme.onSurfaceVariant),
          onTap: _pickBirth,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(strings.birthDateHelp, style: hint),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          key: const ValueKey('stage-dropdown'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: DropdownMenu<String>(
            // Rebuilt from the saved stage (and after a failed save) so the
            // field never shows a choice the server did not keep.
            key: ValueKey('stage-${user.stage}-$_stageResets'),
            initialSelection: user.stage,
            label: Text(strings.reproductiveStage),
            expandedInsets: EdgeInsets.zero,
            enabled: !_savingStage,
            dropdownMenuEntries: [
              for (final stage in const [
                'cycling',
                'perimenopause',
                'menopause',
                'no_cycles'
              ])
                DropdownMenuEntry(
                    value: stage, label: strings.stageLabel(stage)),
            ],
            onSelected: (value) {
              if (value == null || value == user.stage) return;
              _saveStage(value);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(strings.stageSelfReport, style: hint),
        ),
      ],
    ];
    final suggestion = widget.suggestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_updated)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              key: const ValueKey('stage-updated-banner'),
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.stageUpdated,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (suggestion != null)
          ListenableBuilder(
            listenable: suggestion,
            builder: (context, _) {
              final stage = suggestion.stage;
              if (stage == null || suggestion.userId != user.id) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StageSuggestionBanner(
                  key: const ValueKey('settings-stage-suggestion'),
                  strings: strings,
                  stage: stage,
                  busy: _savingStage,
                  onUpdate: () => _saveStage(stage, fromSuggestion: true),
                  onDismiss: suggestion.dismiss,
                ),
              );
            },
          ),
        widget.group(rows),
      ],
    );
  }
}

/// `YYYY-MM` as the first of that month, or null.
DateTime? parseBirthMonth(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return null;
  return DateTime(y, m);
}

/// "Your stage looks like X" with Update and Dismiss, on the calendar and in
/// Settings › Personal.
class StageSuggestionBanner extends StatelessWidget {
  const StageSuggestionBanner({
    super.key,
    required this.strings,
    required this.stage,
    required this.onUpdate,
    required this.onDismiss,
    this.busy = false,
  });

  final Strings strings;
  final String stage;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Same surface as the other notices (sync, reminder hint).
    final fg = scheme.onSecondaryContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: MaterialBanner(
        backgroundColor: scheme.secondaryContainer,
        dividerColor: Colors.transparent,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 0),
        leadingPadding: const EdgeInsetsDirectional.only(end: 12),
        leading: Icon(Icons.auto_awesome_outlined, color: fg),
        content: Text(
          strings.stageSuggestionBody(stage),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
        ),
        actions: [
          TextButton(
            key: const ValueKey('stage-suggestion-dismiss'),
            style: TextButton.styleFrom(foregroundColor: fg),
            onPressed: busy ? null : onDismiss,
            child: Text(strings.dismiss),
          ),
          FilledButton(
            key: const ValueKey('stage-suggestion-update'),
            // The theme's full-width button would push Dismiss to its own row.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: busy ? null : onUpdate,
            child: Text(strings.stageSuggestionUpdate),
          ),
        ],
      ),
    );
  }
}

/// The stage suggestion at the top of the owner's calendar. Left alone it
/// closes after [timeout]; Settings › Personal and the settings dot keep it.
class CalendarStageBanner extends StatefulWidget {
  const CalendarStageBanner({
    super.key,
    required this.suggestion,
    required this.userId,
    required this.strings,
    required this.onUpdate,
  });

  final StageSuggestion suggestion;
  final String userId;
  final Strings strings;
  final Future<void> Function(String stage) onUpdate;

  static const timeout = Duration(seconds: 30);

  @override
  State<CalendarStageBanner> createState() => _CalendarStageBannerState();
}

class _CalendarStageBannerState extends State<CalendarStageBanner> {
  Timer? _timer;
  String? _timing;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.suggestion.addListener(_sync);
    _sync(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant CalendarStageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestion != widget.suggestion) {
      oldWidget.suggestion.removeListener(_sync);
      widget.suggestion.addListener(_sync);
      _sync(rebuild: false);
    }
  }

  @override
  void dispose() {
    widget.suggestion.removeListener(_sync);
    _timer?.cancel();
    super.dispose();
  }

  bool get _visible =>
      widget.suggestion.userId == widget.userId && widget.suggestion.showBanner;

  /// Starts the timeout once per suggested stage while the banner shows.
  void _sync({bool rebuild = true}) {
    final stage = _visible ? widget.suggestion.stage : null;
    if (stage != _timing) {
      _timer?.cancel();
      _timer = null;
      _timing = stage;
      if (stage != null) {
        widget.suggestion.markShown();
        _timer = Timer(CalendarStageBanner.timeout, () {
          if (widget.suggestion.stage == stage) widget.suggestion.hideBanner();
        });
      }
    }
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _update(String stage) async {
    setState(() => _busy = true);
    try {
      await widget.onUpdate(stage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = _visible ? widget.suggestion.stage : null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: stage == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: StageSuggestionBanner(
                key: const ValueKey('calendar-stage-suggestion'),
                strings: widget.strings,
                stage: stage,
                busy: _busy,
                onUpdate: () => _update(stage),
                onDismiss: widget.suggestion.dismiss,
              ),
            ),
    );
  }
}

/// Picks a birth month and year (or clears it); pops `YYYY-MM` or ''.
class _BirthMonthDialog extends StatefulWidget {
  const _BirthMonthDialog({required this.strings, this.initial});

  final Strings strings;
  final DateTime? initial;

  @override
  State<_BirthMonthDialog> createState() => _BirthMonthDialogState();
}

class _BirthMonthDialogState extends State<_BirthMonthDialog> {
  late int? _month = widget.initial?.month;
  late int? _year = widget.initial?.year;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final now = DateTime.now();
    final locale = strings.dateLocale;
    String two(int v) => v.toString().padLeft(2, '0');
    final valid = _month != null &&
        _year != null &&
        !DateTime(_year!, _month!).isAfter(DateTime(now.year, now.month));
    return AlertDialog(
      title: Text(strings.birthDate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            key: const ValueKey('birth-month'),
            initialValue: _month,
            decoration: InputDecoration(labelText: strings.month),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(
                  value: m,
                  child: Text(capitalizeMonth(
                      DateFormat.MMMM(locale).format(DateTime(2000, m)),
                      DateTime(2000, m),
                      locale)),
                ),
            ],
            onChanged: (v) => setState(() => _month = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const ValueKey('birth-year'),
            initialValue: _year,
            decoration: InputDecoration(labelText: strings.year),
            menuMaxHeight: 320,
            items: [
              for (var y = now.year; y >= 1900; y--)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => _year = v),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            key: const ValueKey('birth-clear'),
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(strings.clear),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('birth-save'),
          onPressed: valid
              ? () => Navigator.of(context).pop('$_year-${two(_month!)}')
              : null,
          child: Text(strings.save),
        ),
      ],
    );
  }
}
