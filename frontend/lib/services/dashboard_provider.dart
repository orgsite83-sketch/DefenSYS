import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final dashboardProvider =
    NotifierProvider.family<DashboardNotifier, DashboardState, String>(
      DashboardNotifier.new,
    );

class DashboardState {
  final bool isLoading;
  final Map<String, dynamic>? data;
  final String? error;

  DashboardState({this.isLoading = false, this.data, this.error});

  DashboardState copyWith({
    bool? isLoading,
    Map<String, dynamic>? data,
    String? error,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      error: error,
    );
  }
}

class DashboardNotifier extends Notifier<DashboardState> {
  DashboardNotifier(this.role);

  final String role;

  @override
  DashboardState build() {
    return DashboardState();
  }

  static String get baseUrl => ApiConfig.dashboardsUrl;

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  Future<void> fetchDashboardData() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final url = '$baseUrl/$role/';
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          data: data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error:
              'Failed to load dashboard data. Status: ${response.statusCode}',
        );
      }
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }
}
