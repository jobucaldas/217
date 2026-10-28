import 'dart:async';

import 'package:flutter/widgets.dart';

/// Seeds a freshly-enabled repeat with [minutes] if it is already in the
/// 1-120 range, else the default of 15.
int validOrDefaultRepeatMinutes(int minutes) =>
    minutes >= 1 && minutes <= 120 ? minutes : 15;

/// Debounced, rollback-safe minutes field shared by the owner daily reminder
/// and partner pill alert "repeat every X minutes" settings.
///
/// Owns the [TextEditingController]/[FocusNode] for the field and the
/// debounce timer; the screen holding this still owns `setState` and the
/// preference being saved, calling [onChanged]/[flush] from its own
/// callbacks so the UI rebuilds when [error] changes.
class RepeatMinutesController {
  RepeatMinutesController({
    required this.currentMinutes,
    required this.onFlush,
    this.debounce = const Duration(milliseconds: 700),
  });

  /// Reads the latest saved minutes (e.g. `() => _pref.repeatMinutes`).
  final int Function() currentMinutes;

  /// Fired with a validated 1-120 value once the debounce elapses (or on
  /// blur/submit). Never fired with the already-saved value.
  final ValueChanged<int> onFlush;

  final Duration debounce;

  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  Timer? _saveTimer;
  int? _pendingMinutes;

  /// Error text while the field holds an out-of-range/empty value, or null.
  String? error;

  void attach() {
    textController.text = currentMinutes().toString();
    focusNode.addListener(_onFocusChange);
  }

  void dispose() {
    _cancelTimer();
    focusNode.removeListener(_onFocusChange);
    focusNode.dispose();
    textController.dispose();
  }

  void _cancelTimer() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  void _onFocusChange() {
    if (!focusNode.hasFocus) flush();
  }

  /// Call on every keystroke, inside `setState` so [error] rebuilds the UI.
  /// Saving is debounced so digits typed in quick succession (e.g. "45")
  /// never get locked out by a save of an earlier, partial digit.
  void onChanged(String value, {required String rangeErrorText}) {
    final minutes = int.tryParse(value);
    if (minutes == null || minutes < 1 || minutes > 120) {
      _cancelTimer();
      _pendingMinutes = null;
      error = rangeErrorText;
      return;
    }
    error = null;
    _pendingMinutes = minutes;
    _cancelTimer();
    _saveTimer = Timer(debounce, flush);
  }

  /// Sends the latest valid minutes immediately, cancelling any pending
  /// debounce. A no-op if there is nothing new to save.
  void flush() {
    _cancelTimer();
    final minutes = _pendingMinutes;
    _pendingMinutes = null;
    if (minutes == null || minutes == currentMinutes()) return;
    onFlush(minutes);
  }

  /// True while the user has typed something not yet sent to [onFlush] that
  /// is newer than [attemptedMinutes] (the value of a save about to roll back).
  bool hasNewerUnflushedEdit(int attemptedMinutes) =>
      _saveTimer?.isActive == true ||
      (_pendingMinutes != null && _pendingMinutes != attemptedMinutes);

  /// After a failed save attempt of [attemptedMinutes], resync the field to
  /// [rollbackMinutes] unless the user already typed something newer that
  /// hasn't flushed yet (rewriting the field here would lose that edit).
  void resyncAfterFailedSave(int attemptedMinutes, int rollbackMinutes) {
    if (hasNewerUnflushedEdit(attemptedMinutes)) return;
    _cancelTimer();
    _pendingMinutes = null;
    textController.text = rollbackMinutes.toString();
    error = null;
  }

  /// Turning the repeat off cancels any pending debounce/edit immediately.
  void cancelPending() {
    _cancelTimer();
    _pendingMinutes = null;
    error = null;
  }
}
