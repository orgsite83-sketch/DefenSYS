import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';
import '../network/api_http.dart';
import '../app/app_navigator.dart';
import 'auth_storage_keys.dart';
import '../session/session_providers.dart';
import '../session/session_expired.dart';
import '../session/session_storage.dart';
import '../session/guest_session.dart';
import 'jwt_utils.dart';
import 'terms_acceptance.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthState {
  final bool isLoading;
  final bool isRestoring;
  final Map<String, dynamic>? user;
  final String? error;
  final String? token;
  final String? sessionExpiredMessage;
  final bool sessionRestored;
  final bool requiresTerms;

  const AuthState({
    this.isLoading = false,
    this.isRestoring = true,
    this.user,
    this.error,
    this.token,
    this.sessionExpiredMessage,
    this.sessionRestored = false,
    this.requiresTerms = false,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isRestoring,
    Map<String, dynamic>? user,
    String? error,
    String? token,
    String? sessionExpiredMessage,
    bool? sessionRestored,
    bool? requiresTerms,
    bool clearUser = false,
    bool clearToken = false,
    bool clearSessionMessage = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      user: clearUser ? null : (user ?? this.user),
      error: error,
      token: clearToken ? null : (token ?? this.token),
      sessionExpiredMessage: clearSessionMessage
          ? null
          : (sessionExpiredMessage ?? this.sessionExpiredMessage),
      sessionRestored: sessionRestored ?? this.sessionRestored,
      requiresTerms: requiresTerms ?? this.requiresTerms,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  SessionStorage? _sessionStorage;
  bool _isLoggingOut = false;

  static String get baseUrl => ApiConfig.authUrl;

  bool get isLoggingOut => _isLoggingOut;

  @override
  AuthState build() {
    Future.microtask(_bootstrap);
    return const AuthState(isRestoring: true);
  }

  Future<void> _bootstrap() async {
    final guestJson = readGuestSession();
    if (guestJson != null) {
      try {
        final guest = jsonDecode(guestJson) as Map;
        final token = guest['access'] as String;
        final user = Map<String, dynamic>.from(guest['user'] as Map);
        if (user['role'] == 'guest_panelist' && !shouldRefreshAccess(token, withinSeconds: 0)) {
          state = AuthState(token: token, user: user, isRestoring: false, sessionRestored: true);
          return;
        }
      } catch (_) { /* Return to code entry when stored access is invalid. */ }
      clearGuestSession();
    }
    if (isGuestPortalLocation() || isGuestPortalSession()) {
      state = const AuthState(isRestoring: false);
      return;
    }
    await SessionStorage.clearLegacyPrefs();
    final storage = await SessionStorage.createForRestore();
    if (storage == null) {
      state = state.copyWith(isRestoring: false, sessionRestored: false);
      return;
    }
    _sessionStorage = storage;

    // Fast-path: When access token is still valid in storage (e.g. in-tab refresh),
    // restore the session immediately in 0ms without blocking initial screen data fetches.
    final savedAccess = await storage.readAccess();
    final savedUserJson = await storage.readUserJson();
    if (savedAccess != null &&
        savedAccess.isNotEmpty &&
        !shouldRefreshAccess(savedAccess, withinSeconds: 30) &&
        savedUserJson != null &&
        savedUserJson.isNotEmpty) {
      try {
        final user = Map<String, dynamic>.from(jsonDecode(savedUserJson) as Map);
        final requiresTerms = !await TermsAcceptance.hasAcceptedCurrentTerms();
        state = state.copyWith(
          isRestoring: false,
          sessionRestored: true,
          token: savedAccess,
          user: user,
          requiresTerms: requiresTerms,
        );
        unawaited(fetchCurrentUser(savedAccess));
        return;
      } catch (_) {
        // Fall back to refreshTokens if saved user json parsing failed
      }
    }

    final ok = await refreshTokens(silent: true);
    final requiresTerms = ok && !await TermsAcceptance.hasAcceptedCurrentTerms();
    state = state.copyWith(
      isRestoring: false,
      sessionRestored: ok && state.user != null && state.token != null,
      requiresTerms: requiresTerms,
    );
  }

  /// Guest access is isolated in this browser tab and has no refresh token.
  Future<bool> loginGuest(String code) async {
    state = state.copyWith(isLoading: true, error: null, clearSessionMessage: true);

    try {
      final response = await apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/users/guest-codes/exchange/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code.trim().toUpperCase()}),
      );

      if (response.statusCode != 200) {
        state = state.copyWith(
          isLoading: false,
          error: response.statusCode == 401
              ? 'This invitation is invalid, expired or revoked. Contact your defense coordinator.'
              : response.statusCode == 429
              ? 'Too many attempts. Please wait a minute before trying again.'
              : 'Guest login failed (HTTP ${response.statusCode}).',
        );
        return false;
      }

      final data = _decodeJsonMap(response.body);
      if (data == null) {
        state = state.copyWith(isLoading: false, error: 'Invalid guest login response.');
        return false;
      }

      final access = data['access'] as String?;
      final userRaw = data['user'];
      if (access == null || userRaw is! Map) {
        state = state.copyWith(isLoading: false, error: 'Guest login response missing token.');
        return false;
      }

      final user = Map<String, dynamic>.from(userRaw);
      user['role'] = 'guest_panelist';
      _sessionStorage = null;
      invalidateSessionProviders(ref);
      writeGuestSession(jsonEncode({'access': access, 'user': user}));

      state = state.copyWith(
        isLoading: false,
        isRestoring: false,
        token: access,
        user: user,
        sessionRestored: true,
        requiresTerms: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
      return false;
    }
  }

  bool get isGuestPanelist => state.user?['role'] == 'guest_panelist';

  Future<bool> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {
    state = state.copyWith(isLoading: true, error: null, clearSessionMessage: true);

    try {
      final response = await apiHttpClient.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'remember_me': rememberMe,
        }),
      );

      if (response.statusCode != 200) {
        state = state.copyWith(isLoading: false, error: _loginErrorMessage(response));
        return false;
      }

      final data = _decodeJsonMap(response.body);
      if (data == null) {
        state = state.copyWith(
          isLoading: false,
          error: _htmlResponseMessage(response.statusCode),
        );
        return false;
      }

      final access = data['access'] as String?;
      final refresh = data['refresh'] as String?;
      final userRaw = data['user'];
      if (access == null || refresh == null || userRaw is! Map) {
        state = state.copyWith(
          isLoading: false,
          error: 'Login response missing token or user.',
        );
        return false;
      }

      final user = Map<String, dynamic>.from(userRaw);
      await SessionStorage.persistRememberMeChoice(rememberMe);
      clearGuestSession();
      exitGuestPortalMode();
      _sessionStorage = await SessionStorage.create(rememberMe: rememberMe);
      await _sessionStorage!.clearOtherWebStores();
      await _sessionStorage!.writeRefresh(refresh);
      await _sessionStorage!.writeAccess(access);
      await _sessionStorage!.writeUserJson(jsonEncode(user));
      final requiresTerms = !await TermsAcceptance.hasAcceptedCurrentTerms();

      state = state.copyWith(
        isLoading: false,
        token: access,
        user: user,
        sessionRestored: true,
        requiresTerms: requiresTerms,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
      return false;
    }
  }

  void updateCurrentUser(Map<String, dynamic> userData) {
    final updatedUser = Map<String, dynamic>.from(userData);
    state = state.copyWith(user: updatedUser);

    if (_sessionStorage != null) {
      _sessionStorage!.writeUserJson(jsonEncode(updatedUser));
    }
  }

  Future<void> acceptCurrentTerms() async {
    await TermsAcceptance.recordAcceptance();
    state = state.copyWith(requiresTerms: false);
  }

  Future<bool> refreshTokens({bool silent = false}) async {
    if (isGuestPanelist) return false;
    final storage = _sessionStorage ?? await SessionStorage.createForRestore();
    if (storage == null) return false;
    _sessionStorage = storage;

    final refresh = await storage.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      return false;
    }

    try {
      final response = await apiHttpClient.post(
        Uri.parse('$baseUrl/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );

      if (response.statusCode != 200) {
        if (!silent) {
          await handleSessionExpired(
            reason: response.statusCode == 401
                ? SessionExpiredReason.refreshExpired
                : SessionExpiredReason.refreshFailed,
          );
        }
        return false;
      }

      final data = _decodeJsonMap(response.body);
      if (data == null) {
        if (!silent) {
          await handleSessionExpired(
            reason: SessionExpiredReason.refreshFailed,
          );
        }
        return false;
      }

      final access = data['access'] as String?;
      final newRefresh = data['refresh'] as String? ?? refresh;
      if (access == null) {
        if (!silent) {
          await handleSessionExpired(
            reason: SessionExpiredReason.refreshFailed,
          );
        }
        return false;
      }

      await storage.writeRefresh(newRefresh);
      await storage.writeAccess(access);

      final userJson = await storage.readUserJson();
      if (userJson != null) {
        try {
          final user = Map<String, dynamic>.from(jsonDecode(userJson) as Map);
          state = state.copyWith(token: access, user: user);
        } catch (_) {
          state = state.copyWith(token: access);
        }
      } else {
        state = state.copyWith(token: access);
      }

      final meOk = await fetchCurrentUser(access);
      if (!meOk && state.user == null) {
        final fallbackJson = await storage.readUserJson();
        if (fallbackJson != null) {
          try {
            final user = Map<String, dynamic>.from(jsonDecode(fallbackJson) as Map);
            state = state.copyWith(user: user);
          } catch (_) {}
        }
      }

      return true;
    } catch (_) {
      if (!silent) {
        await handleSessionExpired(
          reason: SessionExpiredReason.refreshFailed,
        );
      }
      return false;
    }
  }

  Future<bool> fetchCurrentUser(String access) async {
    try {
      final response = await apiHttpClient.get(
        Uri.parse('$baseUrl/me/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $access',
        },
      );
      if (response.statusCode != 200) return false;
      final data = _decodeJsonMap(response.body);
      if (data == null) return false;
      final user = Map<String, dynamic>.from(data);
      state = state.copyWith(user: user);
      await _sessionStorage?.writeUserJson(jsonEncode(user));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> handleSessionExpired({
    SessionExpiredReason reason = SessionExpiredReason.refreshFailed,
  }) async {
    if (_isLoggingOut) return;
    final message = isGuestPanelist
        ? 'Your evaluator access has expired or been revoked. Contact your defense coordinator for a new invitation.'
        : sessionExpiredMessageFor(reason);
    await _clearLocalAuth();
    invalidateSessionProviders(ref);
    state = AuthState(
      isRestoring: false,
      sessionExpiredMessage: message,
    );
    _scheduleNavigateToLogin(sessionMessage: message);
  }

  Future<void> logout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    try {
      final refresh = await _sessionStorage?.readRefresh();
      if (refresh != null && refresh.isNotEmpty) {
        try {
          await apiHttpClient.post(
            Uri.parse('$baseUrl/logout/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          );
        } catch (_) {
          // Best-effort server logout; local session is cleared regardless.
        }
      }
      await _clearLocalAuth();
      invalidateSessionProviders(ref);
      state = const AuthState(isRestoring: false);
      _scheduleNavigateToLogin();
    } finally {
      _isLoggingOut = false;
    }
  }

  /// Mobile still uses the navigator stack; web uses auth-gated [MaterialApp.home].
  void _scheduleNavigateToLogin({String? sessionMessage}) {
    if (kIsWeb) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navigateToLogin(sessionMessage: sessionMessage);
    });
  }

  Future<void> _clearLocalAuth() async {
    clearGuestSession();
    await _sessionStorage?.clearAuth();
    _sessionStorage = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthStorageKeys.legacyJwtToken);
    await prefs.remove(AuthStorageKeys.legacyUserData);
  }

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty ||
        trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html')) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _htmlResponseMessage(int statusCode) {
    return 'Server returned HTML (HTTP $statusCode). '
        'Check DJANGO_ALLOWED_HOSTS includes 10.0.2.2 for the Android emulator '
        'and your PC LAN IP for physical devices.';
  }

  static String _loginErrorMessage(http.Response response) {
    final data = _decodeJsonMap(response.body);
    if (data == null) {
      return _htmlResponseMessage(response.statusCode);
    }
    final detail = data['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    return 'Login failed (HTTP ${response.statusCode})';
  }
}
