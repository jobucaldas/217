import 'api/client.dart';
import 'i18n.dart';

/// User-facing text for a failed API call: the server answered with an error
/// ([ApiException]) vs. it could not be reached at all (timeouts, DNS, TLS…).
String friendlyError(Strings strings, Object error) =>
    error is ApiException ? strings.genericError : strings.connectionError;
