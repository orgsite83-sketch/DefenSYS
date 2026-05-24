import 'session_expired.dart';

/// Maps caught errors to provider error strings. Rethrow [SessionExpiredException].
String? providerErrorMessage(Object e) {
  if (e is SessionExpiredException) {
    return null;
  }
  return 'Connection error: $e';
}

bool isSessionExpiredError(Object e) => e is SessionExpiredException;
