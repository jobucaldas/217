import 'message_worker_stub.dart'
    if (dart.library.io) 'message_worker_io.dart' as impl;

/// Turns the periodic background check (Android, about every 15 minutes
/// while online) on or off: new messages and, for a partner, the pill alert.
/// No server push: this is what lets them arrive while 217 is in the
/// background or closed. Turning it off also drops the pending pre-check.
/// Never throws.
Future<void> syncMessageWorker({required bool enabled}) =>
    impl.syncMessageWorker(enabled: enabled);

/// One extra background check at [at] (a partner's pill alert is due soon),
/// replacing any pending one; null cancels it. Never throws.
Future<void> schedulePartnerPrecheck(DateTime? at) =>
    impl.schedulePartnerPrecheck(at);

/// Whether the background worker should be registered: someone is signed in
/// with a role and consent, and has something to check for. Messages count
/// for an owner, or a partner with an active share; a partner with an active
/// share also counts when a PMS or pill alert is on.
bool shouldRunBackgroundWorker({
  required bool signedIn,
  required bool consentRequired,
  required bool hasRole,
  required bool isOwner,
  required bool isPartner,
  required bool shareActive,
  required bool messageNotifications,
  required bool partnerAlertsOn,
}) =>
    signedIn &&
    !consentRequired &&
    hasRole &&
    ((messageNotifications && (isOwner || shareActive)) ||
        (isPartner && shareActive && partnerAlertsOn));
