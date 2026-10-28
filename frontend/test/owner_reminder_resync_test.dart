import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/app.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/notifications/daily_reminder_sync_queue.dart';
import 'package:a217/src/notifications/local_reminders.dart';

/// A consented owner with a configurable reminder preference and an
/// in-memory entries store, mutable through the real upsert/delete endpoints
/// so the day editor exercises the same persistence path as production.
class _OwnerServer {
  bool reminderEnabled = true;
  String reminderTime = '09:00';
  bool repeatEnabled = true;
  int repeatMinutes = 15;
  int reminderPreferenceCalls = 0;
  final Map<String, Map<String, dynamic>> entries = {};

  /// When true, every GET /api/reminders/preferences parks on its own
  /// [Completer] instead of responding, so a test can hold one resync's
  /// preference read open while others arrive behind it.
  bool gateReminderPreferenceReads = false;
  final _pendingPreferenceGates = <Completer<void>>[];

  int get pendingPreferenceGateCount => _pendingPreferenceGates.length;

  /// Releases the oldest still-parked preference read, letting its resync
  /// run continue.
  void releaseOldestPreferenceGate() =>
      _pendingPreferenceGates.removeAt(0).complete();

  /// 1-based count of GET /api/entries calls seen so far.
  int entriesCalls = 0;
  int? _gateAtEntriesCall;
  Completer<void>? _entriesGateCompleter;

  /// Parks the [callNumber]th GET /api/entries call (counting from server
  /// creation) until [releaseGatedEntriesRead] is called. The response it
  /// eventually returns reflects the entries snapshot as of when the
  /// request arrived, mirroring a real server racing a mutation that lands
  /// while the read is still in flight.
  void gateEntriesCall(int callNumber) {
    _gateAtEntriesCall = callNumber;
    _entriesGateCompleter = Completer<void>();
  }

  void releaseGatedEntriesRead() => _entriesGateCompleter?.complete();

  final today = DateTime.now();
  late final todayKey = DateFormat('yyyy-MM-dd').format(today);

  Map<String, dynamic> _session() => {
        'user': {
          'id': 'u1',
          'email': 'owner@example.invalid',
          'name': 'Owner',
          'role': 'owner',
        },
        'share': {'status': 'none', 'can_edit_calendar': true},
        'consent': {'version': 1, 'required': false},
      };

  ApiClient client() => ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          switch (request.method) {
            case 'GET':
              if (path == '/api/auth/session') {
                return http.Response(jsonEncode(_session()), 200);
              }
              if (path == '/api/auth/config') {
                return http.Response(jsonEncode({'authkit': true}), 200);
              }
              if (path == '/api/reminders/preferences') {
                reminderPreferenceCalls++;
                if (gateReminderPreferenceReads) {
                  final gate = Completer<void>();
                  _pendingPreferenceGates.add(gate);
                  await gate.future;
                }
                return http.Response(
                  jsonEncode({
                    'enabled': reminderEnabled,
                    'time': reminderTime,
                    'timezone': 'UTC',
                    'deliverable': true,
                    'repeat_enabled': repeatEnabled,
                    'repeat_minutes': repeatMinutes,
                  }),
                  200,
                );
              }
              if (path == '/api/entries') {
                entriesCalls++;
                final snapshot = entries.values.toList();
                if (entriesCalls == _gateAtEntriesCall) {
                  await _entriesGateCompleter!.future;
                }
                return http.Response(
                  jsonEncode({'entries': snapshot}),
                  200,
                );
              }
              if (path == '/api/cycle') {
                return http.Response(
                  jsonEncode(
                      {'cycle_length': 28, 'period_length': 5, 'estimated': true}),
                  200,
                );
              }
          }
          if (request.method == 'POST' && path.startsWith('/api/entries/')) {
            final date = path.substring('/api/entries/'.length);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final entry = {'date': date, ...body};
            entries[date] = entry;
            return http.Response(jsonEncode(entry), 200);
          }
          if (request.method == 'DELETE' && path.startsWith('/api/entries/')) {
            entries.remove(path.substring('/api/entries/'.length));
            return http.Response('', 204);
          }
          return http.Response('{"error":"not found"}', 404);
        }),
      );
}

/// Records each OS scheduler invocation; production code routes these
/// through [DailyReminderSyncQueue], so one entry means one applied plan.
class _SchedulerLog {
  final calls = <LocalReminderSyncResult Function()>[];
  final enabled = <bool>[];
  final repeatEnabled = <bool>[];
  final todayLogged = <bool>[];

  DailyReminderScheduler get scheduler => ({
        required bool enabled,
        required String timeHhMm,
        required String title,
        required String body,
        bool repeatEnabled = false,
        int repeatMinutes = 15,
        bool todayLogged = false,
      }) async {
        this.enabled.add(enabled);
        this.repeatEnabled.add(repeatEnabled);
        this.todayLogged.add(todayLogged);
        return const LocalReminderSyncResult(LocalReminderSyncStatus.scheduled);
      };
}

Future<void> _tapTakenOnToday(WidgetTester tester, DateTime today) async {
  final grid = find.byKey(ValueKey('${today.year}-${today.month}'));
  await tester.tap(
    find.descendant(of: grid, matching: find.text('${today.day}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Taken').last);
  await tester.pumpAndSettle();
}

Future<void> _tapMissedOnToday(WidgetTester tester, DateTime today) async {
  final grid = find.byKey(ValueKey('${today.year}-${today.month}'));
  await tester.tap(
    find.descendant(of: grid, matching: find.text('${today.day}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Missed').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
      'saving today\'s pill as taken replans with todayLogged, '
      'un-logging restores the repeats', (tester) async {
    final server = _OwnerServer();
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();

    // Startup replan: nothing logged yet, so the repeats are armed.
    expect(log.todayLogged, [false]);
    expect(log.repeatEnabled, [true]);
    final afterStartup = server.reminderPreferenceCalls;
    expect(afterStartup, greaterThan(0));

    await _tapTakenOnToday(tester, server.today);

    expect(server.entries[server.todayKey]?['taken'], isTrue);
    expect(log.todayLogged.last, isTrue, reason: 'logging today cancels its repeats');
    expect(log.enabled.last, isTrue);
    expect(server.reminderPreferenceCalls, afterStartup + 1);

    await _tapMissedOnToday(tester, server.today);

    expect(server.entries[server.todayKey]?['taken'], isFalse);
    expect(log.todayLogged.last, isFalse,
        reason: 'un-logging today restores its repeats');
    expect(server.reminderPreferenceCalls, afterStartup + 2);
  });

  testWidgets('resuming the app refreshes the owner repeat plan',
      (tester) async {
    final server = _OwnerServer();
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();
    expect(log.todayLogged, [false]);
    final afterStartup = server.reminderPreferenceCalls;

    // Another device logged today's pill while this one was backgrounded.
    server.entries[server.todayKey] = {
      'date': server.todayKey,
      'taken': true,
      'notes': '',
      'heart': false,
      'period': false,
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(log.todayLogged.last, isTrue);
    expect(server.reminderPreferenceCalls, afterStartup + 1);
  });

  testWidgets(
      'disabled owner reminder never schedules and skips the network after '
      'the first read', (tester) async {
    final server = _OwnerServer()..reminderEnabled = false;
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();

    expect(log.enabled, isEmpty);
    final afterStartup = server.reminderPreferenceCalls;
    expect(afterStartup, greaterThan(0));

    await _tapTakenOnToday(tester, server.today);

    // Known off already: the resync no-ops without a preference re-read.
    expect(log.enabled, isEmpty);
    expect(server.reminderPreferenceCalls, afterStartup);
  });

  testWidgets('disabled repeat still arms the plain reminder but never a '
      'repeat range', (tester) async {
    final server = _OwnerServer()..repeatEnabled = false;
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();

    expect(log.enabled, [true]);
    expect(log.repeatEnabled, [false]);

    await _tapTakenOnToday(tester, server.today);

    expect(log.enabled.last, isTrue);
    expect(log.repeatEnabled.last, isFalse);
    // Repeat is off: no fresh "logged today" read is needed, so the entries
    // endpoint for it is skipped and todayLogged keeps its default.
    expect(log.todayLogged.last, isTrue);
  });

  testWidgets(
      'a resync that arrives while an earlier one\'s logged-today read is '
      'still pending ends with a schedule reflecting the new state',
      (tester) async {
    final server = _OwnerServer();
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();
    expect(log.todayLogged, [false]);

    // The calendar's own grid load always fetches the current, previous and
    // next month first; the resync's own "logged today" read for the
    // current month is the next /api/entries call after those three. Gate
    // that one so it's still in flight when a second resync arrives.
    server.gateEntriesCall(server.entriesCalls + 4);

    // Earlier resync: reaches its logged-today read and parks there.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(log.todayLogged, [false], reason: 'still parked, no new schedule');

    // Another device logs today's pill while that read is in flight.
    server.entries[server.todayKey] = {
      'date': server.todayKey,
      'taken': true,
      'notes': '',
      'heart': false,
      'period': false,
    };

    // Later resync: arrives mid-flight, so it only marks the run dirty.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(log.todayLogged, [false], reason: 'still parked, no new schedule');

    // Release the stale read: the earlier run finishes (with the old,
    // stale todayLogged), then exactly one trailing run re-reads the fresh
    // preference and entries and produces the final schedule.
    server.releaseGatedEntriesRead();
    await tester.pumpAndSettle();

    expect(log.todayLogged, [false, false, true]);
    expect(log.todayLogged.last, isTrue,
        reason: 'the trailing run must reflect the new logged-today state');
  });

  testWidgets(
      'three overlapping resync calls while a preference read is pending '
      'produce exactly one trailing run', (tester) async {
    final server = _OwnerServer();
    final log = _SchedulerLog();
    final api = server.client();
    await tester.pumpWidget(App217(
      config: api.config,
      api: api,
      dailyReminderScheduler: log.scheduler,
    ));
    await tester.pumpAndSettle();
    // Startup reads preferences both for the reminder hint bubble and for
    // the owner resync itself; only the latter is relevant here.
    final afterStartup = server.reminderPreferenceCalls;

    server.gateReminderPreferenceReads = true;

    // Call A starts its preference read and parks on the gate.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(server.pendingPreferenceGateCount, 1);
    expect(server.reminderPreferenceCalls, afterStartup + 1);

    // Call B arrives while A is in flight: coalesces into A's run instead
    // of starting its own preference read.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(server.pendingPreferenceGateCount, 1);
    expect(server.reminderPreferenceCalls, afterStartup + 1);

    // Call C arrives too: still just one dirty flag, not a second queued run.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(server.pendingPreferenceGateCount, 1);
    expect(server.reminderPreferenceCalls, afterStartup + 1);

    // Let A finish: because B and C arrived mid-flight, exactly one
    // trailing run starts right after, issuing one more preference read.
    server.releaseOldestPreferenceGate();
    await tester.pump();
    expect(server.reminderPreferenceCalls, afterStartup + 2);
    expect(server.pendingPreferenceGateCount, 1);

    // Let the trailing run finish. Nothing arrived while it was running,
    // so no further run starts.
    server.releaseOldestPreferenceGate();
    await tester.pumpAndSettle();
    expect(server.reminderPreferenceCalls, afterStartup + 2);
    expect(log.todayLogged.length, 3, reason: 'startup + A + one trailing run');
  });
}
