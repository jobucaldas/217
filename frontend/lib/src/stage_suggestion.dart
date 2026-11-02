import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// The reproductive stage the server suggests to an owner (`suggested_stage`
/// from `/api/cycle`), and what she did with it on this device.
///
/// The calendar shows it as a banner once per suggested value: it is
/// remembered as seen as soon as it is first displayed ([markShown]) and
/// stays up for that display until it times out ([hideBanner]), is dismissed
/// or accepted. After that it lives in Settings › Personal with a dot on the settings button,
/// until it is accepted ([clear]) or dismissed ([dismiss]). Both are
/// remembered per suggested value, so a different suggestion shows again.
class StageSuggestion extends ChangeNotifier {
  StageSuggestion({AppearancePrefs? prefs}) : _prefs = prefs;

  /// Null keeps the choices in memory only (tests, web without storage).
  final AppearancePrefs? _prefs;

  String? _userId;
  String? _suggested;
  String? _dismissed;
  String? _seen;

  /// The stage whose banner is on screen right now (until it times out).
  String? _showing;

  /// False while what was dismissed or seen is read back from storage, so a
  /// dismissed suggestion does not flash.
  bool _loaded = true;
  int _generation = 0;

  /// The account the suggestion belongs to.
  String? get userId => _userId;

  /// The pending suggestion, or null when there is none or it was dismissed.
  String? get stage => _loaded && _suggested != null && _suggested != _dismissed
      ? _suggested
      : null;

  /// Whether the calendar should show the banner (not timed out yet).
  bool get showBanner => stage != null && (stage != _seen || stage == _showing);

  /// Whether the settings button carries a dot for it.
  bool get showDot => stage != null && !showBanner;

  /// The server's latest suggestion for [userId] (null: none). Call it
  /// outside build: listeners are notified at once.
  void update(String userId, String? suggested) {
    if (_userId != userId) _switchUser(userId);
    if (_suggested == suggested) return;
    _suggested = suggested;
    notifyListeners();
  }

  /// Forgets the previous account and reads what [userId] dismissed or saw.
  void _switchUser(String userId) {
    final generation = ++_generation;
    _userId = userId;
    _suggested = null;
    _dismissed = null;
    _seen = null;
    _showing = null;
    final prefs = _prefs;
    if (prefs == null) return;
    _loaded = false;
    () async {
      String? dismissed;
      String? seen;
      try {
        dismissed = await prefs.stageSuggestionDismissed(userId);
        seen = await prefs.stageSuggestionSeen(userId);
      } catch (_) {
        // Storage unavailable: nothing remembered.
      }
      if (generation != _generation) return;
      _dismissed = dismissed;
      _seen = seen;
      _loaded = true;
      notifyListeners();
    }();
  }

  /// The calendar banner is on screen: remembered at once, so it never
  /// comes back for this stage, but it stays up until [hideBanner].
  void markShown() {
    final current = stage;
    if (current == null || current == _showing) return;
    _showing = current;
    if (current == _seen) return;
    _seen = current;
    _save((prefs, user) => prefs.saveStageSuggestionSeen(user, current));
  }

  /// The calendar banner timed out: from now on Settings and the dot carry it.
  void hideBanner() {
    if (_showing == null) return;
    _showing = null;
    notifyListeners();
  }

  /// Not wanted: hidden everywhere until a different stage is suggested.
  void dismiss() {
    final current = stage;
    if (current == null) return;
    _dismissed = current;
    notifyListeners();
    _save((prefs, user) => prefs.saveStageSuggestionDismissed(user, current));
  }

  /// Accepted (the stage was saved): nothing left to suggest until the
  /// server says otherwise.
  void clear() {
    if (_suggested == null) return;
    _suggested = null;
    notifyListeners();
  }

  void _save(Future<void> Function(AppearancePrefs, String) write) {
    final prefs = _prefs;
    final user = _userId;
    if (prefs == null || user == null) return;
    write(prefs, user).catchError((_) {});
  }
}
