import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/notifications/message_background_check.dart';
import 'package:a217/src/prefs.dart';

/// Server double. `/api/sync/status` answers 304 for the current [etag];
/// [statusCode] overrides every status answer (404: older server, ...).
class _Server {
  int? statusCode;
  String etag = 'e1';
  String role = 'owner';
  bool shareActive = false;
  bool subjectConsent = true;
  String inboxTag = 'i1';
  String calendarTag = 'c1';
  String prefsTag = 'p1';
  String accountTag = 'a1';
  List<Map<String, dynamic>> inbox = [];
  int entryStatus = 404;
  bool taken = false;
  int cycleStatus = 200;
  Map<String, dynamic> alertPref = {
    'pms_enabled': false,
    'pill_enabled': true,
    'pill_time': '21:00',
  };
  bool signOutDuringInbox = false;
  final requests = <String>[];
  final ifNoneMatch = <String?>[];

  late final client = MockClient((request) async {
    requests.add(request.url.path);
    final path = request.url.path;
    if (path == '/api/inbox' && signOutDuringInbox) {
      await const FlutterSecureStorage().delete(key: 'session_token');
    }
    switch (path) {
      case '/api/sync/status':
        ifNoneMatch.add(request.headers['If-None-Match']);
        if (statusCode != null) {
          return http.Response('{"error":"x"}', statusCode!);
        }
        if (request.headers['If-None-Match'] == '"$etag"') {
          return http.Response('', 304, headers: {'etag': '"$etag"'});
        }
        return http.Response(
          jsonEncode({
            'etag': etag,
            'user_id': 'u1',
            'role': role,
            'share_active': shareActive,
            'subject_consent': subjectConsent,
            'tags': {
              'account': accountTag,
              'inbox': inboxTag,
              'calendar': calendarTag,
              'prefs': prefsTag,
            },
          }),
          200,
          headers: {'etag': '"$etag"'},
        );
      case '/api/auth/session':
        return http.Response(
          jsonEncode({
            'user': {'id': 'u1', 'email': 'p@x', 'role': 'partner'},
            'share': {'status': 'active'},
          }),
          200,
        );
      case '/api/inbox':
        return http.Response(jsonEncode({'notes': inbox}), 200);
      case '/api/cycle':
        return http.Response(jsonEncode({}), cycleStatus);
      case '/api/partner-alerts':
        return http.Response(jsonEncode(alertPref), 200);
    }
    if (path.startsWith('/api/entries/')) {
      if (entryStatus != 200) return http.Response('{"error":"x"}', entryStatus);
      return http.Response(
        jsonEncode({
          'date': path.split('/').last,
          'taken': taken,
          'notes': '',
          'heart': false,
          'period': false,
        }),
        200,
      );
    }
    return http.Response('{}', 404);
  });
}

final _config = AppConfig(
  apiBaseUrl: 'https://217.example',
  workosClientId: '',
  redirectUri: 'com.caldasstudios.app217://auth/callback',
);

/// 20:00 on the day entries are read for; the partner's pill alert is 21:00.
final _evening = DateTime(2026, 10, 31, 20);

Map<String, dynamic> _msg(String id, int minute) => {
      'id': id,
      'body': 'hi $id',
      'from_name': 'Ana',
      'created_at': DateTime.utc(2026, 10, 31, 12, minute).toIso8601String(),
    };

void main() {
  late _Server server;
  late List<String> shown;
  late List<String> closures;
  late List<List<PlannedAlert>> plans;
  late List<DateTime?> prechecks;
  late int workerCancelled;
  late bool nagShowing;

  setUp(() {
    server = _Server();
    shown = [];
    closures = [];
    plans = [];
    prechecks = [];
    workerCancelled = 0;
    nagShowing = false;
    FlutterSecureStorage.setMockInitialValues({'session_token': 't'});
  });

  Future<String> savedServer() async =>
      (await ApiClient.storedLogin(_config, const FlutterSecureStorage()))
          .server;

  /// Pretends the app (or an earlier run) saw [etag] and the server's tags.
  Future<void> baseline({
    String etag = 'e0',
    String role = 'partner',
    String calendar = 'c0',
    String prefs = 'p1',
    String account = 'a1',
    String inbox = 'i1',
    String userId = 'u1',
  }) async =>
      AppearancePrefs().saveSyncState(
        await savedServer(),
        SyncStatus(
          etag: etag,
          userId: userId,
          role: role,
          shareActive: true,
          subjectConsent: true,
          tags: SyncTags(
              account: account, inbox: inbox, calendar: calendar, prefs: prefs),
        ),
      );

  Future<void> run({DateTime? at}) => checkMessagesInBackground(
        config: _config,
        client: server.client,
        prefs: AppearancePrefs(),
        deviceLanguage: AppLanguage.en,
        now: at == null ? DateTime.now : () => at,
        show: ({required title, required body}) async {
          shown.add('$title: $body');
          return true;
        },
        schedulePartnerAlerts: (alerts) async {
          plans.add(alerts);
          return alerts.isEmpty
              ? LocalReminderSyncStatus.cancelled
              : LocalReminderSyncStatus.scheduled;
        },
        hasActiveNag: () async => nagShowing,
        showClosure: ({required title, required body}) async {
          closures.add('$title: $body');
          return true;
        },
        schedulePrecheck: (at) async => prechecks.add(at),
        cancelWorker: () async => workerCancelled++,
      );

  Future<SyncStatus?> savedStatus() async =>
      (await AppearancePrefs().syncState())?.status;

  group('older server without /api/sync/status', () {
    setUp(() => server.statusCode = 404);

    test('announces each new message once, after a silent first run',
        () async {
      server.role = 'partner';
      server.inbox = [_msg('a', 1)];
      await run(); // first run on this device: sets the mark only
      expect(shown, isEmpty);
      server.inbox = [_msg('a', 1), _msg('b', 2)];
      await run();
      await run();
      expect(shown, ['New message from Ana: hi b']);
    });

    test('skips signed out meanwhile', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_token': 't',
        '${AppearancePrefs.messagesNotifiedKeyPrefix}u1':
            '2026-10-31T12:00:00Z',
      });
      server.inbox = [_msg('a', 1)];
      server.signOutDuringInbox = true;
      await run();
      expect(server.requests,
          ['/api/sync/status', '/api/auth/session', '/api/inbox']);
      expect(shown, isEmpty);
    });

    test('nothing at all with messages off', () async {
      FlutterSecureStorage.setMockInitialValues(
          {'session_token': 't', AppearancePrefs.messageNotificationsKey: '0'});
      await run();
      expect(server.requests, isEmpty);
    });
  });

  test('signed out removes the worker and asks nothing', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await run();
    expect(server.requests, isEmpty);
    expect(workerCancelled, 1);
  });

  test('skips while the app is in the foreground', () async {
    await baseline();
    await AppearancePrefs().saveMessagesForegroundAt(DateTime.now());
    await run();
    expect(server.requests, isEmpty);
    expect(workerCancelled, 0);
  });

  test('messages off and no partner alerts: not even a status request',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'session_token': 't', AppearancePrefs.messageNotificationsKey: '0'});
    await baseline();
    await run();
    expect(server.requests, isEmpty);
  });

  test('304 costs one request and reads nothing else', () async {
    server.etag = 'e0';
    await baseline(etag: 'e0');
    await run();
    expect(server.requests, ['/api/sync/status']);
    expect(server.ifNoneMatch, ['"e0"']);
    expect(shown, isEmpty);
    expect(plans, isEmpty);
  });

  test('owner: new inbox tag announces once and saves the new state',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'session_token': 't',
      '${AppearancePrefs.messagesNotifiedKeyPrefix}u1': '2026-10-31T12:00:00Z',
    });
    await baseline(role: 'owner');
    server.inbox = [_msg('a', 1)];
    server.inboxTag = 'i2';
    await run();
    expect(server.requests, ['/api/sync/status', '/api/inbox']);
    expect(shown, ['New message from Ana: hi a']);
    expect((await savedStatus())?.etag, 'e1');
    // The state moved on: the next run is a 304.
    server.requests.clear();
    await run();
    expect(server.requests, ['/api/sync/status']);
    expect(shown, hasLength(1));
  });

  test('owner: unchanged inbox tag reads no inbox', () async {
    await baseline(role: 'owner');
    server.calendarTag = 'c9';
    await run();
    expect(server.requests, ['/api/sync/status']);
  });

  group('partner', () {
    setUp(() {
      server.role = 'partner';
      server.shareActive = true;
    });

    Set<int> ids(List<PlannedAlert> alerts) => {for (final a in alerts) a.id};

    test('calendar changed: reads entry, cycle, settings and drops today',
        () async {
      await baseline(calendar: 'c0');
      server.entryStatus = 200;
      server.taken = true;
      await run(at: _evening);
      expect(server.requests, [
        '/api/sync/status',
        '/api/entries/2026-10-31',
        '/api/cycle',
        '/api/partner-alerts',
      ]);
      expect(plans, hasLength(1));
      expect(ids(plans.single), isNot(contains(partnerPillIdBase)));
      expect(ids(plans.single), contains(partnerPillIdBase + 1));
      // Pill logged: nothing to look at before the alert.
      expect(prechecks, [null]);
      expect(await AppearancePrefs().partnerAlertsEnabled('u1'), isTrue);
      expect((await savedStatus())?.etag, 'e1');
    });

    test('no entry today keeps today planned and schedules the pre-check',
        () async {
      await baseline(calendar: 'c0');
      server.entryStatus = 404;
      await run(at: _evening);
      expect(ids(plans.single), contains(partnerPillIdBase));
      expect(prechecks, [DateTime(2026, 10, 31, 20, 57)]);
    });

    test('quiet note only when a pill-not-logged alert was showing', () async {
      await AppearancePrefs().savePartnerOwnerName('u1', 'Ana Maria');
      await baseline(calendar: 'c0');
      server.entryStatus = 200;
      server.taken = true;

      nagShowing = false;
      await run(at: _evening);
      expect(closures, isEmpty);

      await baseline(calendar: 'c0');
      server.etag = 'e2';
      nagShowing = true;
      await run(at: _evening);
      expect(closures, ["217: Ana logged today's pill"]);
    });

    test('unlogged pill never posts the quiet note', () async {
      await baseline(calendar: 'c0');
      server.entryStatus = 404;
      nagShowing = true;
      await run(at: _evening);
      expect(closures, isEmpty);
    });

    test('both alerts off clears the alerts and the pre-check', () async {
      await baseline(calendar: 'c0');
      server.alertPref = {'pms_enabled': false, 'pill_enabled': false};
      await run(at: _evening);
      expect(plans, [const <PlannedAlert>[]]);
      expect(prechecks, [null]);
      expect(await AppearancePrefs().partnerAlertsEnabled('u1'), isFalse);
    });

    test('inactive share cancels alerts without reading the calendar',
        () async {
      await baseline(calendar: 'c0');
      server.shareActive = false;
      await run(at: _evening);
      expect(server.requests, ['/api/sync/status']);
      expect(plans, [const <PlannedAlert>[]]);
      expect(prechecks, [null]);
    });

    test('owner consent withdrawn cancels alerts', () async {
      await baseline(calendar: 'c0');
      server.subjectConsent = false;
      await run(at: _evening);
      expect(plans, [const <PlannedAlert>[]]);
    });

    test('403 cancels the alerts of a saved partner', () async {
      await baseline();
      server.statusCode = 403;
      await run(at: _evening);
      expect(plans, [const <PlannedAlert>[]]);
      expect(prechecks, [null]);
    });

    test('403 leaves an owner alone', () async {
      await baseline(role: 'owner');
      server.statusCode = 403;
      await run(at: _evening);
      expect(plans, isEmpty);
    });

    test('a failed read changes nothing and is retried', () async {
      await baseline(calendar: 'c0');
      server.entryStatus = 500;
      await run(at: _evening);
      expect(plans, isEmpty);
      expect(prechecks, isEmpty);
      expect((await savedStatus())?.etag, 'e0');

      server.entryStatus = 404;
      await run(at: _evening);
      expect(plans, hasLength(1));
      expect((await savedStatus())?.etag, 'e1');
    });

    test('a failed cycle read does not advance the saved state', () async {
      await baseline(calendar: 'c0');
      server.cycleStatus = 500;
      await run(at: _evening);
      expect(plans, isEmpty);
      expect((await savedStatus())?.etag, 'e0');
    });

    test('baseline of another account counts as no baseline', () async {
      await baseline(userId: 'other', calendar: 'c1');
      server.entryStatus = 404;
      await run(at: _evening);
      expect(plans, hasLength(1));
      expect((await savedStatus())?.userId, 'u1');
    });

    test('messages off + partner alerts on runs even without saved baseline',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          {'session_token': 't', AppearancePrefs.messageNotificationsKey: '0'});
      await AppearancePrefs().savePartnerAlertsEnabled('u1', true);
      server.entryStatus = 404;
      await run(at: _evening);
      expect(server.requests, [
        '/api/sync/status',
        '/api/entries/2026-10-31',
        '/api/cycle',
        '/api/partner-alerts',
      ]);
      expect(plans, hasLength(1));
    });

    test('304 replans once on a new local day when partner alerts are on',
        () async {
      await AppearancePrefs().savePartnerAlertsEnabled('u1', true);
      await AppearancePrefs().savePartnerLastPlanDate('u1', '2026-10-31');
      server.etag = 'e0';
      await baseline(etag: 'e0');

      // Same day: 304 reads nothing else.
      await run(at: _evening);
      expect(server.requests, ['/api/sync/status']);
      expect(plans, isEmpty);

      // Next day: 304 replans once and records the new date.
      server.requests.clear();
      server.entryStatus = 404;
      await run(at: DateTime(2026, 11, 1, 20));
      expect(server.requests, [
        '/api/sync/status',
        '/api/entries/2026-11-01',
        '/api/cycle',
        '/api/partner-alerts',
      ]);
      expect(plans, hasLength(1));
      expect(await AppearancePrefs().partnerLastPlanDate('u1'), '2026-11-01');

      // Second run on the new day: back to 304 only.
      server.requests.clear();
      await run(at: DateTime(2026, 11, 1, 20, 15));
      expect(server.requests, ['/api/sync/status']);
      expect(plans, hasLength(1));
    });

    test('failed OS scheduler does not advance saved ETag', () async {
      await baseline(calendar: 'c0');
      server.entryStatus = 404;
      await checkMessagesInBackground(
        config: _config,
        client: server.client,
        prefs: AppearancePrefs(),
        deviceLanguage: AppLanguage.en,
        now: () => _evening,
        schedulePartnerAlerts: (_) async => LocalReminderSyncStatus.failed,
        hasActiveNag: () async => false,
        showClosure: ({required title, required body}) async => true,
        schedulePrecheck: (at) async => prechecks.add(at),
        cancelWorker: () async => workerCancelled++,
      );
      expect((await savedStatus())?.etag, 'e0');
      expect(prechecks, isEmpty);
    });

    test('inactive share clears cached owner name', () async {
      await AppearancePrefs().savePartnerOwnerName('u1', 'Ana Maria');
      await baseline(calendar: 'c0');
      server.shareActive = false;
      await run(at: _evening);
      expect(await AppearancePrefs().partnerOwnerName('u1'), '');
    });
  });

  test('401 is quiet and keeps the saved state', () async {
    await baseline();
    server.statusCode = 401;
    await run();
    expect(server.requests, ['/api/sync/status']);
    expect(plans, isEmpty);
    expect((await savedStatus())?.etag, 'e0');
  });
}
