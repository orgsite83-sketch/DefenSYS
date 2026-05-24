import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'api_http.dart';
import 'app_navigator.dart';
import 'auth_storage_keys.dart';
import 'session_providers.dart';
import 'session_expired.dart';
import 'session_storage.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthState {
  final bool isLoading;
  final bool isRestoring;
  final Map<String, dynamic>? user;
  final String? error;
  final String? token;
  final String? sessionExpiredMessage;
  final bool sessionRestored;

  const AuthState({
    this.isLoading = false,
    this.isRestoring = true,
    this.user,
    this.error,
    this.token,
    this.sessionExpiredMessage,
    this.sessionRestored = false,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isRestoring,
    Map<String, dynamic>? user,
    String? error,
    String? token,
    String? sessionExpiredMessage,
    bool? sessionRestored,
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
    installAuthTabSync(_onTabAuthSync);
    return const AuthState(isRestoring: true);
  }

  void _onTabAuthSync(Map<String, dynamic> data) {
    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    final userJson = data['userJson'] as String?;
    if (access == null || refresh == null || userJson == null) return;
    try {
      final user = Map<String, dynamic>.from(jsonDecode(userJson) as Map);
      state = state.copyWith(token: access, user: user, clearSessionMessage: true);
      _sessionStorage?.writeRefresh(refresh);
      _sessionStorage?.writeUserJson(userJson);
    } catch (_) {
      // Corrupt persisted session payload — treat as logged out.
    }
  }

  Future<void> _bootstrap() async {
    await SessionStorage.clearLegacyPrefs();
    final storage = await SessionStorage.createForRestore();
    if (storage == null) {
      state = state.copyWith(isRestoring: false, sessionRestored: false);
      return;
    }
    _sessionStorage = storage;
    final ok = await refreshTokens(silent: true);
    state = state.copyWith(
      isRestoring: false,
      sessionRestored: ok && state.user != null && state.token != null,
    );
  }

  /// Guest panelist: access token in memory only (no refresh / persistence).
  Future<bool> loginGuest(String code) async {
    if (kIsWeb) {
      state = state.copyWith(
        isLoading: false,
        error: 'Guest panelist access is available on the mobile app only.',
      );
      return false;
    }

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
              ? 'Invalid or expired guest code.'
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
      await _clearLocalAuth();

      state = state.copyWith(
        isLoading: false,
        isRestoring: false,
        token: access,
        user: user,
        sessionRestored: true,
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
      _sessionStorage = await SessionStorage.create(rememberMe: rememberMe);
      await _sessionStorage!.clearOtherWebStores();
      await _sessionStorage!.writeRefresh(refresh);
      await _sessionStorage!.writeUserJson(jsonEncode(user));

      if (kIsWeb && rememberMe) {
        broadcastAuthToOtherTabs(
          access: access,
          refresh: refresh,
          userJson: jsonEncode(user),
        );
      }

      state = state.copyWith(
        isLoading: false,
        token: access,
        user: user,
        sessionRestored: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> refreshTokens({bool silent = false}) async {
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
      state = state.copyWith(token: access);

      final meOk = await fetchCurrentUser(access);
      if (!meOk) {
        final userJson = await storage.readUserJson();
        if (userJson != null) {
          try {
            final user = Map<String, dynamic>.from(jsonDecode(userJson) as Map);
            state = state.copyWith(user: user);
          } catch (_) {
            // Stale userJson fallback after failed /me/.
          }
        }
      }

      if (kIsWeb && storage.rememberMe) {
        final userJson = await storage.readUserJson();
        if (userJson != null) {
          broadcastAuthToOtherTabs(
            access: access,
            refresh: newRefresh,
            userJson: userJson,
          );
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
    final message = sessionExpiredMessageFor(reason);
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
