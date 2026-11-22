import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/models.dart';
import 'package:a217/src/notifications/local_reminders.dart';
import 'package:a217/src/notifications/message_worker.dart';
import 'package:a217/src/prefs.dart';

bool _run({
  bool signedIn = true,
  bool consentRequired = false,
  bool hasRole = true,
  bool isOwner = false,
  bool isPartner = false,
  bool shareActive = false,
  bool messages = false,
  bool alerts = false,
}) =>
    shouldRunBackgroundWorker(
      signedIn: signedIn,
      consentRequired: consentRequired,
      hasRole: hasRole,
      isOwner: isOwner,
      isPartner: isPartner,
      shareActive: shareActive,
      messageNotifications: messages,
      partnerAlertsOn: alerts,
    );

void main() {
  group('shouldRunBackgroundWorker', () {
    test('signed out or without consent or role: never', () {
      expect(_run(signedIn: false, isOwner: true, messages: true), isFalse);
      expect(
          _run(consentRequired: true, isOwner: true, messages: true), isFalse);
      expect(
        _run(
            hasRole: false,
            isPartner: true,
            shareActive: true,
            messages: true,
            alerts: true),
        isFalse,
      );
    });

    test('owner: only for messages', () {
      expect(_run(isOwner: true, messages: true), isTrue);
      expect(_run(isOwner: true, messages: false), isFalse);
      // Partner alerts mean nothing to an owner.
      expect(_run(isOwner: true, alerts: true), isFalse);
    });

    test('partner with a calendar: messages or any alert', () {
      expect(_run(isPartner: true, shareActive: true, messages: true), isTrue);
      expect(_run(isPartner: true, shareActive: true, alerts: true), isTrue);
      expect(
        _run(isPartner: true, shareActive: true, messages: true, alerts: true),
        isTrue,
      );
      expect(_run(isPartner: true, shareActive: true), isFalse);
    });

    test('partner without a calendar: never', () {
      expect(_run(isPartner: true, messages: true, alerts: true), isFalse);
    });
  });

  group('partnerPrecheckAt', () {
    final now = DateTime(2026, 10, 31, 20);
    const pill = PartnerAlertPreference(pillEnabled: true, pillTime: '21:00');

    test('three minutes before today\'s alert', () {
      expect(partnerPrecheckAt(now, pill, false), DateTime(2026, 10, 31, 20, 57));
    });

    test('none when logged, off, or too late', () {
      expect(partnerPrecheckAt(now, pill, true), isNull);
      expect(partnerPrecheckAt(now, const PartnerAlertPreference(), false),
          isNull);
      expect(partnerPrecheckAt(DateTime(2026, 10, 31, 20, 58), pill, false),
          isNull);
      expect(partnerPrecheckAt(DateTime(2026, 10, 31, 22), pill, false),
          isNull);
    });
  });

  group('sync state and partner prefs', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('sync state and app sync state round-trip independently per server',
        () async {
      final prefs = AppearancePrefs();
      expect(await prefs.syncState(), isNull);
      expect(await prefs.appSyncState(), isNull);
      const workerStatus = SyncStatus(
        etag: 'e1',
        userId: 'u1',
        role: 'partner',
        shareActive: true,
        subjectConsent: true,
        tags: SyncTags(account: 'a', inbox: 'i', calendar: 'c', prefs: 'p'),
      );
      const appStatus = SyncStatus(
        etag: 'e0',
        userId: 'u1',
        role: 'partner',
        shareActive: true,
        subjectConsent: true,
        tags: SyncTags(account: 'a', inbox: 'i0', calendar: 'c0', prefs: 'p'),
      );
      await prefs.saveSyncState('https://217.example', workerStatus);
      await prefs.saveAppSyncState('https://217.example', appStatus);
      final savedWorker = await AppearancePrefs().syncState();
      final savedApp = await AppearancePrefs().appSyncState();
      expect(savedWorker?.server, 'https://217.example');
      expect(savedWorker?.status.etag, 'e1');
      expect(savedWorker?.status.userId, 'u1');
      expect(savedWorker?.status.role, 'partner');
      expect(savedWorker?.status.shareActive, isTrue);
      expect(savedWorker?.status.tags.calendar, 'c');
      expect(savedApp?.status.etag, 'e0');
      expect(savedApp?.status.tags.calendar, 'c0');
      await prefs.clearSyncState();
      expect(await prefs.syncState(), isNull);
      expect(await prefs.appSyncState(), isNull);
    });

    test('unreadable saved state counts as none', () async {
      FlutterSecureStorage.setMockInitialValues(
          {AppearancePrefs.syncStateKey: 'not json'});
      expect(await AppearancePrefs().syncState(), isNull);
    });

    test('partner details are kept per account and can be dropped', () async {
      final prefs = AppearancePrefs();
      expect(await prefs.partnerAlertsEnabled('u1'), isFalse);
      expect(await prefs.hasPartnerAlertsForWorker(), isFalse);
      expect(await prefs.partnerOwnerName('u1'), '');
      expect(await prefs.partnerLastPlanDate('u1'), isNull);
      await prefs.savePartnerAlertsEnabled('u1', true);
      await prefs.savePartnerOwnerName('u1', 'Ana');
      await prefs.savePartnerLastPlanDate('u1', '2026-10-31');
      expect(await prefs.partnerAlertsEnabled('u1'), isTrue);
      expect(await prefs.hasPartnerAlertsForWorker(), isTrue);
      expect(await prefs.partnerAlertsEnabled('u2'), isFalse);
      expect(await prefs.partnerOwnerName('u1'), 'Ana');
      expect(await prefs.partnerLastPlanDate('u1'), '2026-10-31');
      await prefs.clearPartnerCache('u1');
      expect(await prefs.partnerAlertsEnabled('u1'), isFalse);
      expect(await prefs.hasPartnerAlertsForWorker(), isFalse);
      expect(await prefs.partnerOwnerName('u1'), '');
      expect(await prefs.partnerLastPlanDate('u1'), isNull);
    });
  });
}
