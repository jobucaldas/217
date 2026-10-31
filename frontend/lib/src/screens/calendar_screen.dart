import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../errors.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications/local_reminders.dart';
import '../notifications/partner_alert_sync_queue.dart';
import '../theme/app_theme.dart';
import 'dialog_actions.dart';
import 'reminder_hint.dart';
import 'share_screens.dart';
import 'day_summary.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.api,
    required this.user,
    required this.strings,
    required this.onOpenSettings,
    this.cycleRefreshSignal,
    this.share = const ShareState(status: 'none'),
    this.onShareChanged,
    this.onInboxSynced,
    this.partnerAlertScheduler,
    this.partnerAlertSyncQueue,
    this.onOwnerReminderResync,
    this.sessionGeneration,
    this.isSessionCurrent,
    this.palette = AppPalette.blue,
    this.showReminderHint = false,
    this.onDismissReminderHint,
  });

  final ApiClient api;
  final User user;
  final ShareState share;
  final Strings strings;
  final VoidCallback onOpenSettings;
  final Listenable? cycleRefreshSignal;
  final ValueChanged<ShareState>? onShareChanged;

  /// The messages screen loaded (and marked read) these messages.
  final ValueChanged<List<InboxMessage>>? onInboxSynced;
  final Future<LocalReminderSyncStatus> Function(List<PlannedAlert>)?
      partnerAlertScheduler;
  final PartnerAlertSyncQueue? partnerAlertSyncQueue;

  /// Owner only: replans the daily reminder and its "pill not logged"
  /// repeats from the latest preference and a fresh "logged today" read.
  /// Called after the cycle (and so today's entry) refreshes, which covers
  /// calendar writes, app resume, and foreground refreshes alike.
  final Future<void> Function()? onOwnerReminderResync;

  /// Read live: a refresh signal can fire before this widget is rebuilt.
  final int Function()? sessionGeneration;
  final bool Function(int generation, String userId)? isSessionCurrent;
  final AppPalette palette;

  /// Bubble pointing at the reminder setting; closes itself after a while.
  final bool showReminderHint;
  final VoidCallback? onDismissReminderHint;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late DateTime _month;
  CycleInfo _cycle = CycleInfo.empty;

  /// Inputs of the last partner-alert sync; month swipes don't replan.
  String? _alertSyncKey;
  int _cycleLoadGeneration = 0;
  int _loadGeneration = 0;
  int _alertSyncGeneration = 0;
  Map<String, Entry> _entries = {};
  Map<String, Entry> _prevEntries = {};
  Map<String, Entry> _nextEntries = {};

  /// Entries per month ("yyyy-M"), kept across month swipes so a month shows
  /// at once while the refresh runs, and edits land on it before the server
  /// answers.
  final Map<String, Map<String, Entry>> _monthCache = {};

  /// Day edits sent but not yet answered. A refresh that lands meanwhile
  /// would put pre-edit data back, so it is dropped; a fresh one follows.
  int _pendingWrites = 0;
  bool _reloadAfterWrites = false;

  /// Moves on every edit and every finished write; a refresh that started
  /// under an older value may carry pre-edit data and is not applied.
  int _writeEpoch = 0;

  /// What the server last confirmed for days being edited, and the newest
  /// edit per day, so a failed write puts the day back without a fetch.
  final Map<String, Entry?> _confirmed = {};
  final Map<String, int> _editSeq = {};
  Future<void> _writeChain = Future.value();
  Entry? _todayEntry;
  String? _error;

  /// Day the bottom summary describes; null follows today.
  DateTime? _selected;

  /// Pixel drag offset: negative = finger left (peek next month).
  double _dragPx = 0;
  bool _monthDragging = false;
  late final AnimationController _monthSnap;
  Animation<double>? _monthSnapAnim;

  /// Web touchpad scroll has no end event: an idle gap ends the gesture,
  /// and a committed month change swallows the rest of it (momentum tail)
  /// so one swipe moves exactly one month.
  Timer? _wheelIdle;
  bool _wheelLocked = false;
  bool _wheelDragging = false;
  static const _wheelIdleGap = Duration(milliseconds: 140);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String get _todayKey => DateFormat('yyyy-MM-dd').format(_today);

  DateTime get _selectedDay {
    final selected = _selected;
    return selected == null || selected.isAfter(_today) ? _today : selected;
  }

  DateTime get _prevMonth => DateTime(_month.year, _month.month - 1);
  DateTime get _nextMonth => DateTime(_month.year, _month.month + 1);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _monthSnap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_monthSnapAnim != null && mounted) {
          setState(() => _dragPx = _monthSnapAnim!.value);
        }
      });
    WidgetsBinding.instance.addObserver(this);
    widget.cycleRefreshSignal?.addListener(_onCycleRefresh);
    _load();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycleRefreshSignal != widget.cycleRefreshSignal) {
      oldWidget.cycleRefreshSignal?.removeListener(_onCycleRefresh);
      widget.cycleRefreshSignal?.addListener(_onCycleRefresh);
    }
  }

  void _onCycleRefresh() {
    if (mounted) _loadCycle();
  }

  /// Back in the foreground: her calendar may have changed (and partner
  /// alerts are replanned from it).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.cycleRefreshSignal?.removeListener(_onCycleRefresh);
    _wheelIdle?.cancel();
    _monthSnap.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final epoch = _writeEpoch;
    // Silent reload: never insert a progress bar into the Column — that
    // reflows/shrinks the month carousel during swipe/chevron month changes.
    setState(() => _error = null);
    try {
      final year = _month.year;
      final month = _month.month;
      final results = await Future.wait([
        widget.api.listEntries(year, month),
        widget.api.listEntries(
          month == 1 ? year - 1 : year,
          month == 1 ? 12 : month - 1,
        ),
        widget.api.listEntries(
          month == 12 ? year + 1 : year,
          month == 12 ? 1 : month + 1,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      // Every month read here is fresh; today's month is one of the three
      // unless the view is two or more months away, then it is read too.
      final fresh = <String, Map<String, Entry>>{
        _monthKey(_month): {for (final e in results[0]) e.date: e},
        _monthKey(_prevMonth): {for (final e in results[1]) e.date: e},
        _monthKey(_nextMonth): {for (final e in results[2]) e.date: e},
      };
      final today = _today;
      final todayMonth = _monthKey(today);
      if (!fresh.containsKey(todayMonth)) {
        try {
          final list = await widget.api.listEntries(today.year, today.month);
          if (!mounted || generation != _loadGeneration) return;
          fresh[todayMonth] = {for (final e in list) e.date: e};
        } catch (err) {
          if (!mounted || generation != _loadGeneration) return;
          if (_handleConsentFailure(err)) return;
          // Keep what we have for today: _todayEntry is never older than
          // the cached month (edits and reads update both).
        }
      }
      final todayFresh = fresh[todayMonth];
      final todayEntry =
          todayFresh != null ? todayFresh[_todayKey] : _todayEntry;
      if (!mounted || generation != _loadGeneration) return;
      if (_pendingWrites > 0) {
        _reloadAfterWrites = true;
        return;
      }
      if (epoch != _writeEpoch) {
        // An edit came and went while this was on its way: ask again.
        unawaited(_load());
        return;
      }
      _confirmed.clear();
      setState(() {
        // Today's month included, so its grid matches _todayEntry.
        _monthCache.addAll(fresh);
        _showCachedMonths();
        _todayEntry = todayEntry;
      });
    } catch (err) {
      if (!mounted || generation != _loadGeneration) return;
      if (_handleConsentFailure(err)) return;
      setState(() => _error = friendlyError(widget.strings, err));
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    await _loadCycle();
  }

  bool _handleConsentFailure(Object err, {bool closeDayEditor = false}) {
    if (err is! ApiException || err.statusCode != 403) return false;
    if (err.message == 'calendar owner consent required') {
      _clearCalendarData(
        error: widget.strings.sharedCalendarOwnerConsentRequired,
      );
      if (closeDayEditor && mounted) Navigator.of(context).maybePop();
      return true;
    }
    if (err.message == 'consent required') {
      _clearCalendarData(cancelPartnerAlerts: false);
      if (closeDayEditor && mounted) Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  void _clearCalendarData({String? error, bool cancelPartnerAlerts = true}) {
    _loadGeneration++;
    _cycleLoadGeneration++;
    final alertGeneration = ++_alertSyncGeneration;
    _alertSyncKey = null;
    if (cancelPartnerAlerts && widget.user.isPartner) {
      if (alertGeneration == _alertSyncGeneration) {
        unawaited(_cancelPartnerAlerts());
      }
    }
    _monthCache.clear();
    _confirmed.clear();
    setState(() {
      _entries = {};
      _prevEntries = {};
      _nextEntries = {};
      _todayEntry = null;
      _cycle = CycleInfo.empty;
      _error = error;
    });
  }

  Future<LocalReminderSyncStatus> _cancelPartnerAlerts() async {
    final queue = widget.partnerAlertSyncQueue;
    if (queue != null) {
      return await queue.cancel() ?? LocalReminderSyncStatus.cancelled;
    }
    return (widget.partnerAlertScheduler ?? syncPartnerAlerts)(const []);
  }

  /// Predictions are a bonus on top of the calendar: failures (older
  /// servers) leave the grid as is.
  Future<void> _loadCycle() async {
    final generation = ++_cycleLoadGeneration;
    final sessionGeneration = widget.sessionGeneration?.call() ?? 0;
    final queueRevision = widget.partnerAlertSyncQueue?.revision;
    CycleInfo cycle;
    try {
      cycle = await widget.api.getCycle(_todayKey);
    } catch (err) {
      if (!mounted || generation != _cycleLoadGeneration) return;
      _handleConsentFailure(err);
      return;
    }
    if (!mounted ||
        generation != _cycleLoadGeneration ||
        !_isCurrentSession(sessionGeneration)) {
      return;
    }
    setState(() => _cycle = cycle);
    if (widget.user.isPartner) {
      await _syncPartnerAlerts(
        cycle,
        sessionGeneration: sessionGeneration,
        queueRevision: queueRevision,
      );
    } else if (widget.user.isOwner) {
      await widget.onOwnerReminderResync?.call();
    }
  }

  bool _isCurrentSession(int generation) =>
      mounted &&
      (widget.isSessionCurrent?.call(generation, widget.user.id) ?? true);

  Future<void> _syncPartnerAlerts(
    CycleInfo cycle, {
    required int sessionGeneration,
    required int? queueRevision,
  }) async {
    final generation = ++_alertSyncGeneration;
    final todayLogged = _todayEntry?.taken == true;
    final key = [
      _todayKey,
      todayLogged,
      widget.share.isActive,
      for (final w in cycle.predictions) w.pmsStart.toIso8601String(),
    ].join('|');
    if (key == _alertSyncKey) return;
    final queue = widget.partnerAlertSyncQueue;
    try {
      final pref = await widget.api.getPartnerAlerts();
      if (!mounted ||
          generation != _alertSyncGeneration ||
          !_isCurrentSession(sessionGeneration)) {
        return;
      }
      // Only touch the OS scheduler once the partner opted in.
      if (queue != null &&
          (queueRevision == null || !queue.isCurrent(queueRevision))) {
        return;
      }
      if (!pref.pmsEnabled && !pref.pillEnabled) {
        if (queue != null) {
          await queue.scheduleBackgroundIfCurrent(
            revision: queueRevision!,
            alerts: const [],
          );
        } else {
          await _cancelPartnerAlerts();
        }
      } else {
        final now = DateTime.now();
        final day = DateFormat.MMMd(widget.strings.dateLocale);
        final alerts = planPartnerAlerts(
          now: now,
          pref: pref,
          cycle: cycle,
          todayLogged: todayLogged,
          pmsTitle: (_) => widget.strings.pmsNotifTitle,
          pmsBody: (window) => widget.strings.pmsNotifBody(
            widget.share.ownerName,
            day.format(window.periodStart),
          ),
          pillTitle: widget.strings.pillNotifTitle,
          pillBody: widget.strings.pillNotifBody(widget.share.ownerName),
        );
        if (queue != null) {
          await queue.scheduleBackgroundIfCurrent(
            revision: queueRevision!,
            alerts: alerts,
          );
        } else {
          await (widget.partnerAlertScheduler ?? syncPartnerAlerts)(alerts);
        }
      }
      if (mounted &&
          generation == _alertSyncGeneration &&
          _isCurrentSession(sessionGeneration)) {
        _alertSyncKey = key;
      }
    } catch (err) {
      if (!mounted || generation != _alertSyncGeneration) return;
      if (_handleConsentFailure(err)) return;
      // Alerts are best-effort; the calendar still works.
    }
  }

  void _shiftMonth(int delta) {
    if (delta == 0) return;
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) {
      setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _dragPx = 0;
        _showCachedMonths();
      });
      _load();
      return;
    }
    // Chevron: animate slide with a light recoil, then commit.
    final target = delta > 0 ? -width : width;
    _animateMonthTo(target, commitDelta: delta);
  }

  void _onMonthDragStart(DragStartDetails _) {
    _wheelDragging = false;
    _monthSnap.stop();
    _monthSnapAnim = null;
    setState(() {
      _monthDragging = true;
      _dragPx = 0;
    });
  }

  void _onMonthDragUpdate(DragUpdateDetails details) {
    setState(() => _dragPx += details.delta.dx);
  }

  void _onMonthDragEnd(DragEndDetails details, double width) {
    final v = details.primaryVelocity ?? 0;
    final threshold = width * 0.22;
    int commit = 0;
    if (_dragPx <= -threshold || v < -480) {
      commit = 1; // next
    } else if (_dragPx >= threshold || v > 480) {
      commit = -1; // previous
    }
    final target = commit == 0 ? 0.0 : (commit > 0 ? -width : width);
    _animateMonthTo(target, commitDelta: commit);
  }

  /// Horizontal two-finger touchpad swipes on web arrive as scroll signals
  /// (native touchpads send pan/zoom, which the drag recognizer handles).
  /// Mouse wheels and vertical scrolls never change the month.
  void _onMonthPointerSignal(PointerSignalEvent event, double width) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.trackpad) {
      return;
    }
    final d = event.scrollDelta;
    if (d.dx.abs() <= d.dy.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final delta = (e as PointerScrollEvent).scrollDelta.dx;
      _wheelIdle?.cancel();
      _wheelIdle = Timer(_wheelIdleGap, _onWheelIdle);
      if (_wheelLocked || _monthSnap.isAnimating || width <= 0) return;
      // A short swipe is enough even on wide layouts.
      final threshold = (width * 0.22).clamp(0.0, 60.0);
      final next = (_dragPx - delta).clamp(-width, width);
      if (next.abs() >= threshold) {
        _wheelLocked = true;
        _wheelDragging = false;
        _dragPx = next;
        _animateMonthTo(next < 0 ? -width : width,
            commitDelta: next < 0 ? 1 : -1);
        return;
      }
      setState(() {
        _wheelDragging = true;
        _monthDragging = true;
        _dragPx = next;
      });
    });
  }

  void _onWheelIdle() {
    _wheelIdle = null;
    _wheelLocked = false;
    if (!mounted || !_wheelDragging) return;
    _wheelDragging = false;
    if (_monthSnap.isAnimating) return;
    // Scroll stopped short of the threshold: spring back.
    _animateMonthTo(0, commitDelta: 0);
  }

  void _animateMonthTo(double target, {required int commitDelta}) {
    final begin = _dragPx;
    // Slight overshoot on settle (recoil), not overblown.
    const recoil = Cubic(0.34, 1.22, 0.64, 1);
    final curve = commitDelta == 0 ? Curves.easeOutCubic : recoil;
    setState(() {
      _monthDragging = false;
      _monthSnapAnim = Tween<double>(begin: begin, end: target).animate(
        CurvedAnimation(parent: _monthSnap, curve: curve),
      );
    });
    _monthSnap.duration = Duration(
      milliseconds: commitDelta == 0 ? 220 : 300,
    );
    _monthSnap.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (commitDelta != 0) {
        setState(() {
          _month = DateTime(_month.year, _month.month + commitDelta);
          _dragPx = 0;
          _monthSnapAnim = null;
          _showCachedMonths();
        });
        _load();
      } else {
        setState(() {
          _dragPx = 0;
          _monthSnapAnim = null;
        });
      }
    });
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _monthKey(DateTime month) => '${month.year}-${month.month}';

  /// Points the three visible grids at the cached months (empty when a month
  /// was never fetched).
  void _showCachedMonths() {
    _prevEntries = _monthCache[_monthKey(_prevMonth)] ?? const {};
    _entries = _monthCache[_monthKey(_month)] ?? const {};
    _nextEntries = _monthCache[_monthKey(_nextMonth)] ?? const {};
  }

  /// Today comes from [_todayEntry]: every successful load and every edit
  /// set it, so it is never older than the cached month (a failed extra
  /// read of today's month leaves both as they were).
  Entry? _visibleEntry(String key) {
    if (key == _todayKey) return _todayEntry;
    return _monthCache[_monthKey(DateTime.parse(key))]?[key];
  }

  void _setLocal(String key, Entry? entry) {
    final month = DateTime.parse(key);
    final cached = _monthCache[_monthKey(month)];
    setState(() {
      if (cached != null || entry != null) {
        final next = Map<String, Entry>.of(cached ?? const {});
        if (entry == null) {
          next.remove(key);
        } else {
          next[key] = entry;
        }
        _monthCache[_monthKey(month)] = next;
      }
      _showCachedMonths();
      if (key == _todayKey) _todayEntry = entry;
    });
  }

  Future<void> _persistDay(String key, DayEditResult result) {
    // On screen before the server has seen it.
    _writeEpoch++;
    _confirmed.putIfAbsent(key, () => _visibleEntry(key));
    final seq = _editSeq[key] = (_editSeq[key] ?? 0) + 1;
    _setLocal(
      key,
      result.clear
          ? null
          : Entry(
              date: key,
              taken: result.taken,
              notes: result.notes,
              heart: result.heart,
              period: result.period,
            ),
    );
    _pendingWrites++;
    // A write still queued when the user signs out must not run as the next
    // account, which shares this client and reads the token per request.
    final isCurrent = widget.isSessionCurrent;
    final userId = widget.user.id;
    final session = widget.sessionGeneration?.call() ?? 0;
    // One write at a time so rapid edits reach the server in order.
    final write = _writeChain.then((_) async {
      try {
        if (isCurrent != null && !isCurrent(session, userId)) return;
        final Entry? saved;
        if (result.clear) {
          await widget.api.deleteEntry(key);
          saved = null;
        } else {
          saved = await widget.api.upsertEntry(
            key,
            taken: result.taken,
            notes: result.notes,
            heart: result.heart,
            period: result.period,
          );
        }
        _confirmed[key] = saved;
      } catch (_) {
        // Back to what the server holds, unless a newer edit of the day is
        // queued (it decides). Then a refresh once the queue drains.
        if (mounted && _editSeq[key] == seq) _setLocal(key, _confirmed[key]);
        _reloadAfterWrites = true;
        rethrow;
      } finally {
        _writeEpoch++;
        _pendingWrites--;
        _afterWrite();
      }
    });
    _writeChain = write.catchError((Object _) {});
    return write;
  }

  /// Entries are already right on screen; once the queue drains, refresh
  /// predictions (or everything, after a failed write).
  void _afterWrite() {
    if (!mounted || _pendingWrites > 0) return;
    if (_reloadAfterWrites) {
      _reloadAfterWrites = false;
      unawaited(_load());
    } else {
      unawaited(_loadCycle());
    }
  }

  /// Selects [day] for the summary; on an editable calendar, also opens
  /// its editor.
  Future<void> _openDay(DateTime day) async {
    setState(() => _selected = _isSameDay(day, _today) ? null : day);
    if (!widget.share.canEditCalendar) {
      return;
    }
    final key = DateFormat('yyyy-MM-dd').format(day);
    final existing = _visibleEntry(key);
    // Persist via onCommit — not the sheet's pop value. Nested note-dialog
    // → sheet pop races on web and can drop the result (note/heart "save"
    // that only sticks after Taken/Missed re-tap).
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DayEditorSheet(
        strings: widget.strings,
        date: key,
        initialTaken: existing?.taken,
        initialNotes: existing?.notes ?? '',
        initialHeart: existing?.heart ?? false,
        initialPeriod: existing?.period ?? false,
        hadEntry: existing != null,
        onCommit: (result) {
          _persistDay(key, result).catchError((Object err) {
            if (mounted && !_handleConsentFailure(err, closeDayEditor: true)) {
              setState(() => _error = friendlyError(widget.strings, err));
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.dateLocale;
    final monthLabel = DateFormat.yMMMM(locale).format(_month);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final todayStatus = _todayEntry == null || _todayEntry!.taken == null
        ? widget.strings.unrecorded
        : (_todayEntry!.taken! ? widget.strings.taken : widget.strings.missed);
    final todayColor = _todayEntry == null || _todayEntry!.taken == null
        ? scheme.onSurfaceVariant
        : (_todayEntry!.taken!
            ? App217Colors.statusTaken(brightness, widget.palette)
            : App217Colors.statusMissed(brightness, widget.palette));
    final humanDate = DateFormat.MMMMd(locale).format(_today);
    final selectedDay = _selectedDay;
    final selectedKey = DateFormat('yyyy-MM-dd').format(selectedDay);
    final selectedEntry = _visibleEntry(selectedKey);
    final selectedNotes = selectedEntry?.notes.trim() ?? '';
    final pmsColor = App217Colors.pms(brightness, widget.palette);
    final periodColor = App217Colors.period(brightness, widget.palette);
    final todayKind = _cycle.kindOf(_today);
    final inPms = todayKind == CycleDayKind.pms;
    final next = _cycle.nextWindow(_today);
    final shortDay = DateFormat.MMMd(locale);
    final String? cycleLine;
    if (next == null) {
      cycleLine = _cycle.note == 'pms_suppressed_menopause'
          ? null
          : widget.share.canEditCalendar
              ? widget.strings.cycleHintOwner
              : null;
    } else if (inPms) {
      cycleLine = widget.strings.cyclePmsNow(shortDay.format(next.periodStart));
    } else if (todayKind == CycleDayKind.predictedPeriod) {
      cycleLine = widget.strings.cyclePeriodNow;
    } else if (next.pmsStart.year < 2) {
      cycleLine =
          widget.strings.cycleNextNoPms(shortDay.format(next.periodStart));
    } else {
      cycleLine = widget.strings.cycleNext(
        shortDay.format(next.periodStart),
        shortDay.format(next.pmsStart),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.brand),
        actions: [
          InboxButton(
            api: widget.api,
            strings: widget.strings,
            share: widget.share,
            onSynced: widget.onInboxSynced,
          ),
          IconButton(
            tooltip: widget.strings.settings,
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.share.canEditCalendar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    widget.strings.readOnlyCalendar,
                    style: text.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.strings.today,
                      style: text.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(humanDate, style: text.headlineMedium),
                        ),
                        Text(
                          todayStatus,
                          style: text.titleLarge?.copyWith(color: todayColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (cycleLine != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Row(
                    key: const ValueKey('cycle-line'),
                    children: [
                      Icon(
                        Icons.water_drop_outlined,
                        size: 16,
                        color: inPms ? pmsColor : periodColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cycleLine,
                          style: text.bodyMedium?.copyWith(
                            color: inPms
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontWeight: inPms ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_cycle.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Row(
                    key: const ValueKey('cycle-stage-note'),
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.strings.cycleStageNote(_cycle.note),
                          style: text.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _LegendDot(
                      color:
                          App217Colors.statusTaken(brightness, widget.palette),
                      label: widget.strings.legendTaken,
                    ),
                    _LegendDot(
                      color:
                          App217Colors.statusMissed(brightness, widget.palette),
                      label: widget.strings.legendMissed,
                    ),
                    _LegendDot(
                      color: scheme.onSurfaceVariant,
                      label: widget.strings.legendUnrecorded,
                      outlined: true,
                    ),
                    _LegendDot(
                      color: periodColor,
                      label: widget.strings.legendPeriod,
                      icon: Icons.water_drop,
                    ),
                    _LegendDot(
                      color: pmsColor,
                      label: widget.strings.legendPms,
                      dashed: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: widget.strings.previousMonth,
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: text.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: widget.strings.nextMonth,
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              // Errors overlay the carousel instead of inserting Column chrome
              // that would shrink the month grid.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pageW = constraints.maxWidth;
                    final gridBottom = _MonthGrid.contentHeight(
                      _month,
                      constraints.biggest,
                      bottomInset: 12,
                    );
                    // The note goes in the room the grid leaves below itself,
                    // when there is enough for a line or two.
                    final noteRoom = constraints.maxHeight - gridBottom - 12;
                    final showNote = selectedNotes.isNotEmpty && noteRoom >= 52;
                    // Web touchpad swipes arrive as scroll signals; native
                    // touchpad pan/zoom reaches the horizontal drag below.
                    final carousel = Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: (e) => _onMonthPointerSignal(e, pageW),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _onMonthDragStart,
                        onHorizontalDragUpdate: _onMonthDragUpdate,
                        onHorizontalDragEnd: (d) => _onMonthDragEnd(d, pageW),
                        child: ClipRect(
                          key: const ValueKey('month-carousel'),
                          child: IgnorePointer(
                            ignoring: _monthDragging || _monthSnap.isAnimating,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Transform.translate(
                                  offset: Offset(_dragPx - pageW, 0),
                                  child: _MonthGrid(
                                    key: ValueKey(
                                      '${_prevMonth.year}-${_prevMonth.month}',
                                    ),
                                    month: _prevMonth,
                                    today: _today,
                                    entries: _prevEntries,
                                    cycle: _cycle,
                                    onDayTap: _openDay,
                                    todayLabel: widget.strings.today,
                                    weekdayLabels:
                                        widget.strings.weekdayInitials,
                                    palette: widget.palette,
                                    bottomInset: 12,
                                    selected: selectedDay,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(_dragPx, 0),
                                  child: _MonthGrid(
                                    key: ValueKey(
                                      '${_month.year}-${_month.month}',
                                    ),
                                    month: _month,
                                    today: _today,
                                    entries: _entries,
                                    cycle: _cycle,
                                    onDayTap: _openDay,
                                    todayLabel: widget.strings.today,
                                    weekdayLabels:
                                        widget.strings.weekdayInitials,
                                    palette: widget.palette,
                                    bottomInset: 12,
                                    selected: selectedDay,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(_dragPx + pageW, 0),
                                  child: _MonthGrid(
                                    key: ValueKey(
                                      '${_nextMonth.year}-${_nextMonth.month}',
                                    ),
                                    month: _nextMonth,
                                    today: _today,
                                    entries: _nextEntries,
                                    cycle: _cycle,
                                    onDayTap: _openDay,
                                    todayLabel: widget.strings.today,
                                    weekdayLabels:
                                        widget.strings.weekdayInitials,
                                    palette: widget.palette,
                                    bottomInset: 12,
                                    selected: selectedDay,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    if (!showNote) return carousel;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        carousel,
                        Positioned(
                          left: 16,
                          right: 16,
                          top: gridBottom + 4,
                          bottom: 8,
                          child: DayNotePanel(notes: selectedNotes),
                        ),
                      ],
                    );
                  },
                ),
              ),
              DaySummaryBar(
                strings: widget.strings,
                day: selectedDay,
                isToday: _isSameDay(selectedDay, _today),
                entry: selectedEntry,
                cycleKind: _cycle.kindOf(selectedDay),
                palette: widget.palette,
                onEdit: widget.share.canEditCalendar
                    ? () => _openDay(selectedDay)
                    : null,
              ),
            ],
          ),
          if (_error != null)
            Positioned(
              left: 20,
              right: 20,
              top: 8,
              child: Material(
                key: const ValueKey('calendar-error'),
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onErrorContainer,
                        ),
                        onPressed: _load,
                        child: Text(widget.strings.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.showReminderHint &&
              widget.onDismissReminderHint != null &&
              _error == null)
            Positioned(
              left: 20,
              right: 20,
              top: 8,
              child: ReminderHint(
                key: const ValueKey('reminder-hint'),
                strings: widget.strings,
                onDismiss: widget.onDismissReminderHint!,
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
    this.dashed = false,
    this.icon,
  });

  final Color color;
  final String label;
  final bool outlined;

  /// Dashed rounded square, as drawn around expected PMS days.
  final bool dashed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final mark = DayMark(
      color: color,
      outlined: outlined,
      dashed: dashed,
      icon: icon,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.entries,
    required this.onDayTap,
    required this.todayLabel,
    required this.weekdayLabels,
    required this.palette,
    required this.bottomInset,
    this.cycle = CycleInfo.empty,
    this.selected,
  });

  /// Grid padding, weekday row and week rows: how far down [month] reaches
  /// in a page of [size]. Mirrors the layout in [build].
  static double contentHeight(
    DateTime month,
    Size size, {
    required double bottomInset,
  }) {
    final rows = _rowCount(month);
    final rowsHeight = size.height - 4 - bottomInset - _weekdayRowHeight;
    final rowHeight = math.min(rowsHeight / rows, (size.width - 24) / 7 * 1.15);
    return 4 + _weekdayRowHeight + rowHeight * rows;
  }

  static const double _weekdayRowHeight = 28;

  static int _rowCount(DateTime month) {
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((leading + days) / 7).ceil();
  }

  final DateTime month;
  final DateTime today;
  final Map<String, Entry> entries;
  final CycleInfo cycle;
  final Future<void> Function(DateTime day) onDayTap;
  final String todayLabel;
  final List<String> weekdayLabels;
  final AppPalette palette;
  final double bottomInset;

  /// Day described by the summary bar; outlined when it is not today.
  final DateTime? selected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sunday-first
    final rowCount = _rowCount(month);

    Widget slot(int index) {
      if (index < leading || index >= leading + daysInMonth) {
        return const SizedBox.expand();
      }
      final day = index - leading + 1;
      final date = DateTime(month.year, month.month, day);
      return _DayCell(
        day: date,
        today: today,
        todayLabel: todayLabel,
        entry: entries[DateFormat('yyyy-MM-dd').format(date)],
        cycleKind: cycle.kindOf(date),
        onTap: onDayTap,
        palette: palette,
        selected: selected != null &&
            selected!.year == date.year &&
            selected!.month == date.month &&
            selected!.day == date.day,
      );
    }

    // Exact-fit rows: each week gets 1/rowCount of remaining height so the
    // full month never crops on short or ultrawide viewports (GridView
    // aspect-ratio clamps used to overflow).
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, bottomInset),
      child: Column(
        children: [
          SizedBox(
            height: _weekdayRowHeight,
            child: Row(
              children: [
                for (final label in weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Rows share the height but never get taller than 1.15x the
                // cell width, so portrait phones keep compact cells instead of
                // stretching them across the screen.
                final rowHeight = math.min(
                  constraints.maxHeight / rowCount,
                  constraints.maxWidth / 7 * 1.15,
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var row = 0; row < rowCount; row++)
                        SizedBox(
                          height: rowHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var col = 0; col < 7; col++)
                                Expanded(
                                  child: slot(row * 7 + col),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.todayLabel,
    required this.entry,
    required this.onTap,
    required this.palette,
    this.cycleKind = CycleDayKind.none,
    this.selected = false,
  });

  final DateTime day;
  final DateTime today;
  final bool selected;
  final String todayLabel;
  final Entry? entry;
  final CycleDayKind cycleKind;
  final Future<void> Function(DateTime day) onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    Color? bg;
    if (entry?.taken != null) {
      bg = entry!.taken!
          ? App217Colors.cellTaken(brightness, palette)
          : App217Colors.cellMissed(brightness, palette);
    }
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final isFuture = day.isAfter(today);
    final emptyBg = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: isFuture ? 0.05 : 0.08),
      scheme.surface,
    );
    final onCell = bg == null
        ? scheme.onSurface
        : App217Colors.onFilledCell(brightness, palette);
    final hasNote = entry != null && entry!.notes.trim().isNotEmpty;
    final hasHeart = entry != null && entry!.heart;
    final loggedPeriod = entry != null && entry!.period;
    final predictedPeriod =
        !loggedPeriod && cycleKind == CycleDayKind.predictedPeriod;
    final isPms = cycleKind == CycleDayKind.pms;
    final periodColor =
        bg == null ? App217Colors.period(brightness, palette) : onCell;

    return InkWell(
      onTap: isFuture ? null : () => onTap(day),
      borderRadius: BorderRadius.circular(12),
      // Expected PMS days: a light, sparsely dashed ring in the gap around
      // the cell (an estimate, like the outlined predicted-period drop), so
      // it reads on top of Taken/Missed fills and next to today's border.
      child: CustomPaint(
        key: isPms ? ValueKey('pms-${day.month}-${day.day}') : null,
        foregroundPainter: isPms
            ? DashedRingPainter(
                color: App217Colors.pms(brightness, palette),
                radius: 14,
                strokeWidth: 1.5,
                dash: 3,
                gap: 4,
              )
            : null,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bg ?? emptyBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isToday
                  ? scheme.primary
                  : selected
                      ? scheme.onSurface
                      : scheme.outline.withValues(alpha: 0.55),
              width: isToday || selected ? 2.2 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      color: onCell,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (isToday)
                    Text(
                      todayLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: bg == null ? scheme.primary : onCell,
                      ),
                    ),
                  if (hasNote || hasHeart || loggedPeriod || predictedPeriod)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (loggedPeriod)
                          Icon(
                            Icons.water_drop,
                            key: ValueKey('period-${day.month}-${day.day}'),
                            size: 11,
                            color: periodColor,
                          ),
                        if (predictedPeriod)
                          Icon(
                            Icons.water_drop_outlined,
                            key: ValueKey(
                              'predicted-period-${day.month}-${day.day}',
                            ),
                            size: 11,
                            color: periodColor,
                          ),
                        if ((loggedPeriod || predictedPeriod) &&
                            (hasHeart || hasNote))
                          const SizedBox(width: 2),
                        if (hasHeart)
                          Icon(Icons.favorite, size: 11, color: onCell),
                        if (hasHeart && hasNote) const SizedBox(width: 2),
                        if (hasNote)
                          Icon(Icons.sticky_note_2_outlined,
                              size: 11, color: onCell),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DayEditResult {
  const DayEditResult.save({
    required this.taken,
    required this.notes,
    this.heart = false,
    this.period = false,
  }) : clear = false;
  const DayEditResult.clear()
      : clear = true,
        taken = null,
        notes = '',
        heart = false,
        period = false;

  final bool clear;
  final bool? taken;
  final String notes;
  final bool heart;
  final bool period;
}

/// Day mark bottom sheet: status + note affordance aligned with the date.
class DayEditorSheet extends StatefulWidget {
  const DayEditorSheet({
    super.key,
    required this.strings,
    required this.date,
    required this.initialTaken,
    required this.initialNotes,
    required this.hadEntry,
    this.initialHeart = false,
    this.initialPeriod = false,
    this.onCommit,
  });

  final Strings strings;
  final String date;
  final bool? initialTaken;
  final String initialNotes;
  final bool initialHeart;
  final bool initialPeriod;
  final bool hadEntry;

  /// When set (production calendar), persist immediately — do not rely on the
  /// modal sheet's `Navigator.pop` value surviving a nested note dialog.
  final ValueChanged<DayEditResult>? onCommit;

  @override
  State<DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<DayEditorSheet> {
  late bool? _taken = widget.initialTaken;
  late String _notes = widget.initialNotes;
  late bool _heart = widget.initialHeart;
  late bool _period = widget.initialPeriod;
  late bool _hadEntry = widget.hadEntry;

  DayEditResult _saveResult({
    required bool? taken,
    required String notes,
    required bool heart,
  }) =>
      DayEditResult.save(
        taken: taken,
        notes: notes.trim(),
        heart: heart,
        period: _period,
      );

  /// Heart and period toggles persist at once and keep the sheet open, like
  /// notes.
  void _persistToggle() {
    final status = _taken ?? widget.initialTaken;
    final DayEditResult result;
    if (status == null && _notes.trim().isEmpty && !_heart && !_period) {
      if (!_hadEntry) return;
      result = const DayEditResult.clear();
      _hadEntry = false;
    } else {
      result = _saveResult(taken: status, notes: _notes, heart: _heart);
      _hadEntry = true;
    }
    final onCommit = widget.onCommit;
    if (onCommit != null) {
      onCommit(result);
    } else if (Navigator.of(context).canPop()) {
      // Test harness without onCommit: return the result via sheet pop.
      Navigator.pop(context, result);
    }
  }

  void _toggleHeart() {
    setState(() => _heart = !_heart);
    _persistToggle();
  }

  void _togglePeriod() {
    setState(() => _period = !_period);
    _persistToggle();
  }

  void _emit(DayEditResult result) {
    final onCommit = widget.onCommit;
    if (onCommit != null) {
      onCommit(result);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
      return;
    }
    // Test harness / no callback: return result via sheet pop.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context, result);
    }
  }

  void _commitSave({String? notes, bool? heart}) {
    final taken = _taken;
    if (taken == null) {
      // Status commits always have a selection; note Done uses _editNote.
      return;
    }
    _emit(
      _saveResult(
        taken: taken,
        notes: notes ?? _notes,
        heart: heart ?? _heart,
      ),
    );
  }

  void _commitClear() {
    _emit(const DayEditResult.clear());
  }

  void _onStatusChanged(Set<bool> value) {
    if (value.isEmpty) {
      // Unselect — clear existing day mark (and note/heart) immediately.
      if (_hadEntry) {
        _commitClear();
      } else {
        setState(() => _taken = null);
      }
      return;
    }
    // Taken / Missed commits status + current note/heart and closes.
    _taken = value.first;
    _commitSave();
  }

  Future<void> _editNote() async {
    // Capture before the dialog await — sheet may unmount on web when the
    // nested route settles, and we still must persist note/heart.
    final onCommit = widget.onCommit;
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _NoteDialog(
        strings: widget.strings,
        initialNotes: _notes,
      ),
    );
    if (result == null) return;

    final notes = result;
    final heart = _heart;
    final status = _taken ?? widget.initialTaken;

    if (mounted) {
      setState(() {
        _notes = notes;
        if (status != null) _taken = status;
      });
    }

    // Empty note + no heart + no status → clear any existing note-only entry.
    // Keep the day sheet open — only the note dialog closed.
    if (status == null && notes.trim().isEmpty && !heart && !_period) {
      if (_hadEntry) {
        _hadEntry = false;
        final clear = const DayEditResult.clear();
        if (onCommit != null) {
          onCommit(clear);
        } else if (mounted && Navigator.of(context).canPop()) {
          // Test harness without onCommit: return clear via sheet pop.
          Navigator.pop(context, clear);
        }
      }
      return;
    }

    // Persist note/heart even when Taken/Missed is unset (Em aberto).
    // Close only the note dialog (already dismissed by showDialog); keep the
    // day sheet open so Taken/Missed/heart remain tappable without reopen.
    final save = _saveResult(taken: status, notes: notes, heart: heart);
    _hadEntry = true;
    if (onCommit != null) {
      onCommit(save);
    } else if (mounted && Navigator.of(context).canPop()) {
      // Test harness without onCommit: return save via sheet pop.
      Navigator.pop(context, save);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.strings.dateLocale;
    final human = DateFormat.yMMMMd(locale).format(DateTime.parse(widget.date));
    final hasNote = _notes.trim().isNotEmpty;
    final periodColor = App217Colors.period(Theme.of(context).brightness);
    final heartColor = App217Colors.intimacy(Theme.of(context).brightness);
    final periodInk =
        ThemeData.estimateBrightnessForColor(periodColor) == Brightness.dark
            ? Colors.white
            : const Color(0xFF0B1220);
    // Outside tap dismisses; no Cancel / Save — Done or Taken/Missed commit.
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  human,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              _MarkButton(
                key: const ValueKey('day-heart-toggle'),
                tooltip: widget.strings.heartLabel,
                selected: _heart,
                color: heartColor,
                ink: heartColor,
                solid: false,
                icon: Icons.favorite_border,
                selectedIcon: Icons.favorite,
                onPressed: _toggleHeart,
              ),
              const SizedBox(width: 4),
              _MarkButton(
                key: const ValueKey('day-period-toggle'),
                tooltip: widget.strings.periodLabel,
                selected: _period,
                color: periodColor,
                ink: periodInk,
                icon: Icons.water_drop_outlined,
                selectedIcon: Icons.water_drop,
                onPressed: _togglePeriod,
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: widget.strings.notes,
                onPressed: _editNote,
                icon: Icon(
                  hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(
                value: true,
                label: Text(widget.strings.takenLabel),
              ),
              ButtonSegment(
                value: false,
                label: Text(widget.strings.missedLabel),
              ),
            ],
            selected: {if (_taken != null) _taken!},
            onSelectionChanged: _onStatusChanged,
          ),
        ],
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.strings, required this.initialNotes});

  final Strings strings;
  final String initialNotes;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNotes);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasText = _controller.text.trim().isNotEmpty;
    final onField = scheme.onSurface;
    final fieldFill = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.06),
      scheme.surface,
    );
    return AlertDialog(
      backgroundColor: scheme.surface,
      title: Text(
        widget.strings.notes,
        style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        cursorColor: scheme.primary,
        style: textTheme.bodyLarge?.copyWith(
          color: onField,
          fontSize: 17,
          height: 1.35,
        ),
        decoration: InputDecoration(
          hintText: widget.strings.addNote,
          hintStyle: textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
          filled: true,
          fillColor: fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 1.6),
          ),
        ),
      ),
      actions: [
        // No Cancel — barrier / outside tap dismisses without saving.
        DialogActionRow(
          secondary: hasText
              ? DialogLinkButton(
                  onPressed: () => Navigator.pop(
                    context,
                    '',
                  ),
                  label: widget.strings.clearNote,
                )
              : null,
          primary: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 48),
            ),
            onPressed: () => Navigator.pop(
              context,
              _controller.text.trim(),
            ),
            child: Text(widget.strings.done),
          ),
        ),
      ],
    );
  }
}

/// Round toggle beside the note button: tinted when off, solid when marked,
/// in the colour the mark has on the calendar.
class _MarkButton extends StatelessWidget {
  const _MarkButton({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.ink,
    required this.icon,
    required this.selectedIcon,
    required this.onPressed,
    this.solid = true,
  });

  final String tooltip;
  final bool selected;
  final Color color;
  final Color ink;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onPressed;

  /// Selected state fills the button with [color]; otherwise it stays a tint
  /// and only the symbol turns [ink].
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (solid ? color : color.withValues(alpha: 0.28))
              : color.withValues(alpha: 0.16),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : color,
        ),
      ),
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon),
    );
  }
}
