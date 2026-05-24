import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final gradeCenterProvider =
    NotifierProvider<GradeCenterNotifier, GradeCenterState>(
      GradeCenterNotifier.new,
    );

class GradeCenterState {
  final bool isLoading;
  final bool isSaving;
  final bool isRefreshingGrade;
  final List<Map<String, dynamic>> grades;
  final List<String> yearLevels;
  final List<String> statuses;
  final List<Map<String, dynamic>> scopes;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final Map<String, Map<String, dynamic>> groupSettings;
  final List<Map<String, dynamic>> capstoneStages;
  final String search;
  final String yearLevel;
  final String status;
  final String scope;
  final String? error;
  final String? message;

  const GradeCenterState({
    this.isLoading = false,
    this.isSaving = false,
    this.isRefreshingGrade = false,
    this.grades = const [],
    this.yearLevels = const [],
    this.statuses = const [],
    this.scopes = const [],
    this.counts = const {},
    this.activeSemester,
    this.groupSettings = const {},
    this.capstoneStages = const [],
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
    bool? isRefreshingGrade,
    List<Map<String, dynamic>>? grades,
    List<String>? yearLevels,
    List<String>? statuses,
    List<Map<String, dynamic>>? scopes,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    Map<String, Map<String, dynamic>>? groupSettings,
    List<Map<String, dynamic>>? capstoneStages,
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
      isRefreshingGrade: isRefreshingGrade ?? this.isRefreshingGrade,
      grades: grades ?? this.grades,
      yearLevels: yearLevels ?? this.yearLevels,
      statuses: statuses ?? this.statuses,
      scopes: scopes ?? this.scopes,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      groupSettings: groupSettings ?? this.groupSettings,
      capstoneStages: capstoneStages ?? this.capstoneStages,
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
      final queryParameters = <String, String>{
        if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
        if (nextYearLevel.isNotEmpty) 'year_level': nextYearLevel,
        if (nextStatus.isNotEmpty) 'status': nextStatus,
      };
      if (nextScope.isNotEmpty) {
        queryParameters['scope'] = nextScope;
      }
      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParameters);
      final response = await _client.get(uri);

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

  /// Fetches one grade row (rebuilds peer aggregates on the server) and merges into state.
  Future<bool> refreshGrade(int gradeId) async {
    state = state.copyWith(isRefreshingGrade: true, clearError: true);

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/$gradeId/'),
        
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final grade = payload['grade'];
        if (grade is Map) {
          final updated = Map<String, dynamic>.from(grade);
          state = state.copyWith(
            isRefreshingGrade: false,
            grades: _mergeGradeIntoList(state.grades, updated),
            clearError: true,
          );
          return true;
        }
        state = state.copyWith(isRefreshingGrade: false);
        return false;
      }

      state = state.copyWith(
        isRefreshingGrade: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isRefreshingGrade: false,
        error: 'Connection error: $e',
      );
      return false;
    }
  }

  Future<bool> syncGrades() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/sync/'),
        
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
      final response = await _client.patch(
        Uri.parse('$baseUrl/$gradeId/'),
        
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
      final response = await _client.post(
        Uri.parse('$baseUrl/$gradeId/publish/'),
        
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

  Future<bool> updateGroupSettings({
    required String scope,
    required String stageLabel,
    bool? isOfficiallyComplete,
    bool? peerGradingEnabled,
  }) async {
    if (isOfficiallyComplete == null && peerGradingEnabled == null) {
      return true;
    }
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final body = <String, dynamic>{
        'scope': scope,
        'stage_label': stageLabel,
      };
      if (isOfficiallyComplete != null) {
        body['is_officially_complete'] = isOfficiallyComplete;
      }
      if (peerGradingEnabled != null) {
        body['peer_grading_enabled'] = peerGradingEnabled;
      }
      final response = await _client.patch(
        Uri.parse('$baseUrl/group-settings/'),
        
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final merged = Map<String, Map<String, dynamic>>.from(state.groupSettings);
        final updated = payload['group_settings'];
        if (updated is Map) {
          for (final entry in updated.entries) {
            if (entry.value is Map) {
              merged[entry.key.toString()] = Map<String, dynamic>.from(
                entry.value as Map,
              );
            }
          }
        }
        var message = 'Event settings updated.';
        final autoPublish = payload['auto_publish'] ?? payload['auto_finalize'];
        if (autoPublish is Map && isOfficiallyComplete == true) {
          final readyCount = autoPublish['ready_for_archive_count'] ??
              autoPublish['published_count'];
          if (readyCount is int && readyCount > 0) {
            message =
                'Event marked officially complete. $readyCount passed team(s) are ready to archive in Repository Audit.';
          } else if (scope == 'pit' || scope == 'capstone') {
            message =
                'Stage marked officially complete. Passed teams with complete scores are ready to archive in Repository Audit.';
          }
        }
        state = state.copyWith(
          isSaving: false,
          groupSettings: merged,
          message: message,
          clearError: true,
        );
        if (isOfficiallyComplete == true &&
            (payload['auto_publish'] != null || payload['auto_finalize'] != null)) {
          await fetchGrades(scope: state.scope.isNotEmpty ? state.scope : scope);
        }
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
      final response = await _client.patch(
        Uri.parse('$baseUrl/evaluation-settings/'),
        
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

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


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
      groupSettings: _readGroupSettings(payload['group_settings']),
      capstoneStages: _readMapList(payload['capstone_stages']),
      message: successMessage,
      clearError: true,
    );
  }

  Map<String, Map<String, dynamic>> _readGroupSettings(dynamic value) {
    if (value is! Map) {
      return {};
    }
    final result = <String, Map<String, dynamic>>{};
    for (final entry in value.entries) {
      if (entry.value is Map) {
        result[entry.key.toString()] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    return result;
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

  List<Map<String, dynamic>> _mergeGradeIntoList(
    List<Map<String, dynamic>> grades,
    Map<String, dynamic> updated,
  ) {
    final updatedId = updated['id'];
    var found = false;
    final merged = grades.map((grade) {
      if (grade['id'] == updatedId ||
          grade['id']?.toString() == updatedId?.toString()) {
        found = true;
        return updated;
      }
      return grade;
    }).toList();
    if (!found) {
      merged.add(updated);
    }
    return merged;
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
