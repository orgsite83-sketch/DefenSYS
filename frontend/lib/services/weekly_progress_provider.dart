import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'api_http.dart';

final weeklyProgressProvider =
    NotifierProvider<WeeklyProgressNotifier, WeeklyProgressState>(
      WeeklyProgressNotifier.new,
    );

class WeeklyProgressState {
  final bool isLoading;
  final List<Map<String, dynamic>> reports;
  final int count;
  final String? error;
  final String? message;

  const WeeklyProgressState({
    this.isLoading = false,
    this.reports = const [],
    this.count = 0,
    this.error,
    this.message,
  });

  WeeklyProgressState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? reports,
    int? count,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return WeeklyProgressState(
      isLoading: isLoading ?? this.isLoading,
      reports: reports ?? this.reports,
      count: count ?? this.count,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class WeeklyProgressNotifier extends Notifier<WeeklyProgressState> {
  static String get baseUrl => ApiConfig.weeklyProgressUrl;

  @override
  WeeklyProgressState build() {
    return const WeeklyProgressState();
  }

  Future<void> fetchReports() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await apiHttpClient.get(
        Uri.parse('$baseUrl/'),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isLoading: false,
          reports: _readMapList(data['reports']),
          count: data['count'] ?? 0,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      throw Exception('No authentication token found.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) {
          return data['detail'].toString();
        }
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
          return firstValue.toString();
        }
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }

    return 'Request failed. Status: ${response.statusCode}';
  }
}
