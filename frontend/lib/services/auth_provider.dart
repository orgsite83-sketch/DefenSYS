import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'api_http.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthState {
  final bool isLoading;
  final Map<String, dynamic>? user;
  final String? error;
  final String? token;

  AuthState({this.isLoading = false, this.user, this.error, this.token});

  AuthState copyWith({bool? isLoading, Map<String, dynamic>? user, String? error, String? token}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
      token: token ?? this.token,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _loadToken();
    return AuthState();
  }

  static final String baseUrl = ApiConfig.authUrl;

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final userStr = prefs.getString('user_data');
    if (token != null && userStr != null) {
      state = state.copyWith(token: token, user: jsonDecode(userStr));
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await apiHttpClient.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = _decodeJsonMap(response.body);
        if (data == null) {
          state = state.copyWith(
            isLoading: false,
            error: _htmlResponseMessage(response.statusCode),
          );
          return false;
        }

        final token = data['access'] as String?;
        final userRaw = data['user'];
        if (token == null || userRaw is! Map) {
          state = state.copyWith(
            isLoading: false,
            error: 'Login response missing token or user.',
          );
          return false;
        }
        final user = Map<String, dynamic>.from(userRaw);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('user_data', jsonEncode(user));

        state = state.copyWith(isLoading: false, token: token, user: user);
        return true;
      }

      final errorMsg = _loginErrorMessage(response);
      state = state.copyWith(isLoading: false, error: errorMsg);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
      return false;
    }
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_data');
    state = AuthState();
  }
}
