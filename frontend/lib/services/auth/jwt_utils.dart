import 'dart:convert';

/// Seconds since epoch when the JWT expires, or null if unparsable.
int? jwtExpiryEpochSeconds(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    var payload = parts[1];
    final mod = payload.length % 4;
    if (mod > 0) {
      payload += '=' * (4 - mod);
    }
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded);
    if (map is! Map<String, dynamic>) return null;
    final exp = map['exp'];
    if (exp is int) return exp;
    if (exp is num) return exp.toInt();
    return null;
  } catch (_) {
    return null;
  }
}

/// True when [token] is missing or expires within [withinSeconds].
bool shouldRefreshAccess(String? token, {int withinSeconds = 90}) {
  if (token == null || token.isEmpty) return true;
  final exp = jwtExpiryEpochSeconds(token);
  if (exp == null) return true;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return now >= exp - withinSeconds;
}
