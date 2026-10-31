import 'api/client.dart';
import 'i18n.dart';

/// User-facing text for a failed API call: the server answered with an error
/// ([ApiException]) vs. it could not be reached at all (timeouts, DNS, TLS…).
String friendlyError(Strings strings, Object error) {
  if (error is! ApiException) return strings.connectionError;
  // Retrying cannot help until the calendar owner agrees to the notice.
  if (error.message == 'calendar owner consent required') {
    return strings.sharedCalendarOwnerConsentRequired;
  }
  if (error.message == 'partner consent required') {
    return strings.partnerConsentRequired;
  }
  return strings.genericError;
}
