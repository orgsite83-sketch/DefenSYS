import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

final gradeCenterProvider =
    NotifierProvider<GradeCenterNotifier, GradeCenterState>(
      GradeCenterNotifier.new,
    );

class GradeCenterState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> grades;
  final List<String> yearLevels;
  final List<String> statuses;
  final List<Map<String, dynamic>> scopes;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String search;
  final String yearLevel;
  final String status;
  final String scope;
  final String? error;
  final String? message;

  const GradeCenterState({
    this.isLoading = false,
    this.isSaving = false,
    this.grades = const [],
    this.yearLevels = const [],
    this.statuses = const [],
    this.scopes = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.yearLevel = '',
    this.status = '',
    this.scope = '',
    this.error,
    this.message,
  });

  GradeCenterState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? grades,
    List<String>? yearLevels,
    List<String>? statuses,
    List<Map<String, dynamic>>? scopes,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? yearLevel,
    String? status,
    String? scope,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return GradeCenterState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      grades: grades ?? this.grades,
      yearLevels: yearLevels ?? this.yearLevels,
      statuses: statuses ?? this.statuses,
      scopes: scopes ?? this.scopes,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      search: search ?? this.search,
      yearLevel: yearLevel ?? this.yearLevel,
      status: status ?? this.status,
      scope: scope ?? this.scope,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class GradeCenterNotifier extends Notifier<GradeCenterState> {
    static String get baseUrl => ApiConfig.gradeCenterUrl;

  @override
  GradeCenterState build() {
    return const GradeCenterState();
  }

  Future<void> fetchGrades({
    String? search,
    String? yearLevel,
    String? status,
    String? scope,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextStatus = status ?? state.status;
    final nextScope = scope ?? state.scope;

    state = state.copyWith(
      isLoading: state.grades.isEmpty,
      isSaving: false,
      search: nextSearch,
      yearLevel: nextYearLevel,
      status: nextStatus,
      scope: nextScope,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextYearLevel.isNotEmpty) 'year_level': nextYearLevel,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          if (nextScope.isNotEmpty) 'scope': nextScope,
        },
      );
      final response = await http.get(uri, headers: await _headers());

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyPayload(payload, successMessage: successMessage);
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> syncGrades() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sync/'),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final sync = payload['sync'] is Map
            ? Map<String, dynamic>.from(payload['sync'])
            : const <String, dynamic>{};
        _applyPayload(
          payload,
          successMessage:
              'Grade rows synced. Created ${sync['created'] ?? 0}, updated ${sync['updated'] ?? 0}.',
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> updateGrade(int gradeId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/$gradeId/'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchGrades(successMessage: 'Grade scores updated.');
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> publishGrade(int gradeId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$gradeId/publish/'),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        await fetchGrades(
          successMessage: 'Grade published and team result updated.',
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  /// Admin-only: toggles stored on the active semester (Capstone peer / adviser).
  Future<bool> updateCapstoneEvaluationSettings({
    bool? peerEvaluationEnabled,
    bool? adviserGradingEnabled,
  }) async {
    if (peerEvaluationEnabled == null && adviserGradingEnabled == null) {
      return true;
    }
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final body = <String, dynamic>{};
      if (peerEvaluationEnabled != null) {
        body['capstone_peer_evaluation_enabled'] = peerEvaluationEnabled;
      }
      if (adviserGradingEnabled != null) {
        body['capstone_adviser_grading_enabled'] = adviserGradingEnabled;
      }
      final response = await http.patch(
        Uri.parse('$baseUrl/evaluation-settings/'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final sem = payload['active_semester'];
        state = state.copyWith(
          isSaving: false,
          activeSemester: sem is Map
              ? Map<String, dynamic>.from(sem)
              : state.activeSemester,
          clearActiveSemester: sem == null,
          message: 'Capstone evaluation settings updated.',
          clearError: true,
        );
        return true;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
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

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      grades: _readMapList(payload['grades']),
      yearLevels: _readStringList(payload['year_levels']),
      statuses: _readStringList(payload['statuses']),
      scopes: _readMapList(payload['scopes']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      message: successMessage,
      clearError: true,
    );
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value.map((item) => item.toString()).toList();
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
