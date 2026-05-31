import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_http.dart';
import 'auth_provider.dart';
import 'jwt_utils.dart';
import 'session_expired.dart';

final authenticatedHttpClientProvider = Provider<AuthenticatedHttpClient>((ref) {
  return AuthenticatedHttpClient(ref);
});

/// Central HTTP client: Bearer access, proactive + reactive refresh, session redirect.
class AuthenticatedHttpClient {
  AuthenticatedHttpClient(this._ref);

  final Ref _ref;
  Completer<bool>? _refreshCompleter;

  AuthNotifier get _auth => _ref.read(authProvider.notifier);

  bool get _isGuestPanelist => _auth.isGuestPanelist;

  Future<void> _onAuthFailure({
    SessionExpiredReason reason = SessionExpiredReason.refreshFailed,
  }) async {
    if (_auth.isLoggingOut) {
      throw SessionExpiredException(
        sessionExpiredMessageFor(reason),
        reason,
      );
    }
    await _auth.handleSessionExpired(reason: reason);
    throw SessionExpiredException(
      sessionExpiredMessageFor(reason),
      reason,
    );
  }

  Future<void> _ensureReady() async {
    var auth = _ref.read(authProvider);
    var attempts = 0;
    while (auth.isRestoring && attempts < 200) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      auth = _ref.read(authProvider);
      attempts++;
    }
    if (auth.isRestoring) {
      throw SessionExpiredException();
    }
  }

  Future<String?> _accessToken({bool allowRefresh = true}) async {
    await _ensureReady();
    var token = _ref.read(authProvider).token;
    if (allowRefresh && !_isGuestPanelist && shouldRefreshAccess(token)) {
      final ok = await _refreshSingleFlight();
      if (!ok) {
        await _onAuthFailure(reason: SessionExpiredReason.refreshExpired);
      }
      token = _ref.read(authProvider).token;
    }
    if (token == null || token.isEmpty) {
      await _onAuthFailure(reason: SessionExpiredReason.browserSessionEnded);
    }
    return token;
  }

  Future<bool> _refreshSingleFlight() async {
    if (_isGuestPanelist) return false;
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final ok = await _auth.refreshTokens(silent: true);
      _refreshCompleter!.complete(ok);
      return ok;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Map<String, String> _authHeaders(String token, Map<String, String>? extra) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?extra,
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    Map<String, String>? headers,
    bool retryOn401 = true,
  }) async {
    final token = await _accessToken();
    var response = await request(_authHeaders(token!, headers));

    if (response.statusCode == 401 && retryOn401) {
      final refreshed = await _refreshSingleFlight();
      if (!refreshed) {
        await _onAuthFailure();
      }
      final retryToken = _ref.read(authProvider).token;
      if (retryToken == null) {
        await _onAuthFailure();
      }
      response = await request(_authHeaders(retryToken!, headers));
      if (response.statusCode == 401) {
        await _onAuthFailure();
      }
    }

    return response;
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    return _send(
      (h) => apiHttpClient.get(uri, headers: h),
      headers: headers,
    );
  }

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      (h) => apiHttpClient.post(uri, headers: h, body: body),
      headers: headers,
    );
  }

  Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      (h) => apiHttpClient.put(uri, headers: h, body: body),
      headers: headers,
    );
  }

  Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      (h) => apiHttpClient.patch(uri, headers: h, body: body),
      headers: headers,
    );
  }

  Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      (h) => apiHttpClient.delete(uri, headers: h, body: body),
      headers: headers,
    );
  }

  /// Returns headers with a valid Bearer token for multipart / PDF viewers.
  Future<Map<String, String>> authHeaders({Map<String, String>? extra}) async {
    final token = await _accessToken();
    return _authHeaders(token!, extra);
  }

  /// Fetches file bytes from [fileRef] via the authenticated media proxy.
  Future<Uint8List> fetchAuthenticatedFile(String fileRef) async {
    final url = ApiConfig.authenticatedMediaUrl(fileRef);
    final response = await get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load file (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  Future<http.StreamedResponse> sendAuthenticated(
    http.BaseRequest request, {
    bool retryOn401 = true,
  }) async {
    await _ensureReady();
    var token = await _accessToken();
    request.headers['Authorization'] = 'Bearer $token';

    var streamed = await apiHttpClient.send(request);
  if (streamed.statusCode != 401 || !retryOn401) {
      return streamed;
    }

    final refreshed = await _refreshSingleFlight();
    if (!refreshed) {
      await _onAuthFailure();
    }
    token = _ref.read(authProvider).token;
    if (token == null) {
      await _onAuthFailure();
    }
    request.headers['Authorization'] = 'Bearer $token';
    streamed = await apiHttpClient.send(request);
    if (streamed.statusCode == 401) {
      await _onAuthFailure();
    }
    return streamed;
  }
}

/// Decode helper for providers (no logging).
Map<String, dynamic>? decodeJsonMap(String body) {
  final trimmed = body.trimLeft();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
