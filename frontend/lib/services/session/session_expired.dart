/// Why the user was signed out (for login banner copy).
enum SessionExpiredReason {
  accessExpired,
  refreshExpired,
  refreshFailed,
  browserSessionEnded,
}

/// Thrown when refresh failed and the app is redirecting to login.
class SessionExpiredException implements Exception {
  SessionExpiredException([this.message, this.reason]);

  final String? message;
  final SessionExpiredReason? reason;

  @override
  String toString() => message ?? sessionExpiredMessageFor(reason);
}

String sessionExpiredMessageFor(SessionExpiredReason? reason) {
  switch (reason) {
    case SessionExpiredReason.accessExpired:
      return 'Your sign-in timed out after 8 hours of inactivity. Please sign in again.';
    case SessionExpiredReason.refreshExpired:
      return 'You were signed out after 7 days without activity (Remember me) '
          'or 12 hours (standard login). Please sign in again.';
    case SessionExpiredReason.browserSessionEnded:
      return 'This browser session ended. Sign in again '
          '(use Remember me to stay signed in across restarts for up to 7 days).';
    case SessionExpiredReason.refreshFailed:
    case null:
      return 'We could not renew your session. Please sign in again.';
  }
}
