/// Thrown when refresh failed and the app is redirecting to login.
class SessionExpiredException implements Exception {
  SessionExpiredException([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'Session expired';
}
