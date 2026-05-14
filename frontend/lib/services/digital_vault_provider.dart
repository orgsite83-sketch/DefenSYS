import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

final digitalVaultProvider =
    NotifierProvider<DigitalVaultNotifier, DigitalVaultState>(
      DigitalVaultNotifier.new,
    );

class DigitalVaultState {
  final bool isLoading;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> options;
  final String search;
  final String type;
  final String yearLevel;
  final String stage;
  final String academicYear;
  final String? error;

  const DigitalVaultState({
    this.isLoading = false,
    this.entries = const [],
    this.counts = const {},
    this.options = const {},
    this.search = '',
    this.type = '',
    this.yearLevel = '',
    this.stage = '',
    this.academicYear = '',
    this.error,
  });

  DigitalVaultState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? entries,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? options,
    String? search,
    String? type,
    String? yearLevel,
    String? stage,
    String? academicYear,
    String? error,
    bool clearError = false,
  }) {
    return DigitalVaultState(
      isLoading: isLoading ?? this.isLoading,
      entries: entries ?? this.entries,
      counts: counts ?? this.counts,
      options: options ?? this.options,
      search: search ?? this.search,
      type: type ?? this.type,
      yearLevel: yearLevel ?? this.yearLevel,
      stage: stage ?? this.stage,
      academicYear: academicYear ?? this.academicYear,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class DigitalVaultNotifier extends Notifier<DigitalVaultState> {
    static String get baseUrl => ApiConfig.digitalVaultUrl;

  @override
  DigitalVaultState build() {
    return const DigitalVaultState();
  }

  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? stage,
    String? academicYear,
  }) async {
    final nextSearch = search ?? state.search;
    final nextType = type ?? state.type;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextStage = stage ?? state.stage;
    final nextAcademicYear = academicYear ?? state.academicYear;

    state = state.copyWith(
      isLoading: state.entries.isEmpty,
      search: nextSearch,
      type: nextType,
      yearLevel: nextYearLevel,
      stage: nextStage,
      academicYear: nextAcademicYear,
      clearError: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextType.isNotEmpty) 'type': nextType,
          if (nextYearLevel.isNotEmpty) 'year_level': nextYearLevel,
          if (nextStage.isNotEmpty) 'stage': nextStage,
          if (nextAcademicYear.isNotEmpty) 'academic_year': nextAcademicYear,
        },
      );

      final response = await http.get(uri, headers: await _headers());
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isLoading: false,
          entries: _readMapList(payload['entries']),
          counts: payload['counts'] is Map
              ? Map<String, dynamic>.from(payload['counts'])
              : const {},
          options: payload['options'] is Map
              ? Map<String, dynamic>.from(payload['options'])
              : const {},
          clearError: true,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
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
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }
    return 'Request failed. Status: ${response.statusCode}';
  }
}
