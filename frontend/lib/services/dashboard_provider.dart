import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'api_http.dart';

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

  Future<void> fetchDashboardData() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'No authentication token found.',
        );
        return;
      }

      final url = '$baseUrl/$role/';
      print('Fetching dashboard data from: $url');

      final response = await apiHttpClient.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Dashboard response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Dashboard data received: ${data.keys}');
        if (data['team'] != null) {
          print('Team: ${data['team']['name']}');
        } else {
          print('Warning: No team data in response');
        }
        
        state = state.copyWith(
          isLoading: false,
          data: data,
        );
      } else {
        print('Dashboard error: ${response.statusCode} - ${response.body}');
        state = state.copyWith(
          isLoading: false,
          error:
              'Failed to load dashboard data. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Dashboard exception: $e');
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }
}
