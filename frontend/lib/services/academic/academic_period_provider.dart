import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/data_refresh_provider.dart';

final academicPeriodProvider =
    NotifierProvider<AcademicPeriodNotifier, AcademicPeriodState>(
      AcademicPeriodNotifier.new,
    );

class AcademicPeriodState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> schoolYears;
  final Map<String, dynamic>? activeSemester;
  final int? selectedSchoolYearId;
  final String? error;
  final String? message;

  const AcademicPeriodState({
    this.isLoading = false,
    this.isSaving = false,
    this.schoolYears = const [],
    this.activeSemester,
    this.selectedSchoolYearId,
    this.error,
    this.message,
  });

  AcademicPeriodState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? schoolYears,
    Map<String, dynamic>? activeSemester,
    int? selectedSchoolYearId,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return AcademicPeriodState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      schoolYears: schoolYears ?? this.schoolYears,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      selectedSchoolYearId: selectedSchoolYearId ?? this.selectedSchoolYearId,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class AcademicPeriodNotifier extends Notifier<AcademicPeriodState> {
  static String get baseUrl => ApiConfig.academicPeriodsUrl;

  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState();
  }

  Future<void> fetchPeriods({String? successMessage}) async {
    state = state.copyWith(
      isLoading: state.schoolYears.isEmpty,
      isSaving: false,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(Uri.parse('$baseUrl/'));

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

  Future<bool> addSchoolYear(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Enter a school year first.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/'),

        body: jsonEncode({'school_year': trimmed}),
      );

      if (response.statusCode == 201) {
        await fetchPeriods(successMessage: 'School year $trimmed added.');
        _markDependentDataChanged();
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

  Future<bool> updateSchoolYear(int schoolYearId, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Enter a school year first.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$schoolYearId/'),
        body: jsonEncode({'school_year': trimmed}),
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyPayload(
          payload,
          successMessage: 'School year updated to $trimmed.',
        );
        _markDependentDataChanged();
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

  Future<bool> deleteSchoolYear(int schoolYearId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$schoolYearId/'),
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final msg = payload['detail']?.toString() ?? 'School year deleted.';
        if (state.selectedSchoolYearId == schoolYearId) {
          state = state.copyWith(selectedSchoolYearId: null);
        }
        _applyPayload(payload, successMessage: msg);
        _markDependentDataChanged();
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

  Future<bool> addSemester(
    int schoolYearId,
    String label, {
    String? startsOn,
    String? endsOn,
    bool setActive = false,
    Map<String, dynamic> activation = const {},
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/$schoolYearId/semesters/'),

        body: jsonEncode({
          'label': label,
          'starts_on': startsOn,
          'ends_on': endsOn,
          'set_active': setActive,
          ...activation,
        }),
      );

      if (response.statusCode == 201) {
        await fetchPeriods(
          successMessage: setActive
              ? '$label added and activated.'
              : '$label added.',
        );
        _markDependentDataChanged();
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

  Future<bool> deleteSemester(int semesterId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/semesters/$semesterId/'),
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final msg = payload['detail']?.toString() ?? 'Semester deleted.';
        _applyPayload(payload, successMessage: msg);
        _markDependentDataChanged();
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

  Future<Map<String, dynamic>?> fetchCreateTransitionPreview(
    int schoolYearId,
    Map<String, dynamic> draft,
  ) async {
    state = state.copyWith(clearError: true);
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/$schoolYearId/semesters/transition-preview/'),
        body: jsonEncode({...draft, 'set_active': true}),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      state = state.copyWith(error: _errorFromResponse(response));
    } catch (e) {
      state = state.copyWith(error: 'Connection error: $e');
    }
    return null;
  }

  Future<bool> updateSemesterCalendar(
    int semesterId,
    String startsOn,
    String endsOn,
  ) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/semesters/$semesterId/'),
        body: jsonEncode({'starts_on': startsOn, 'ends_on': endsOn}),
      );
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map;
        final count =
            (payload['calendar_issues'] as Map?)?['out_of_range_count'] ?? 0;
        await fetchPeriods(
          successMessage: count == 0
              ? 'Semester dates saved.'
              : 'Semester dates saved. $count existing schedules need date review.',
        );
        _markDependentDataChanged();
        return true;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
    return false;
  }

  Future<bool> setSemesterActive(int semesterId, bool isActive) async {
    if (isActive) {
      return activateSemester(semesterId);
    }

    state = state.copyWith(
      error:
          'Choose another semester to activate instead of deactivating the active semester directly.',
      clearMessage: true,
    );
    return false;
  }

  Future<Map<String, dynamic>?> fetchTransitionPreview(int semesterId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/semesters/$semesterId/transition-preview/'),
      );

      if (response.statusCode == 200) {
        state = state.copyWith(isSaving: false);
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return null;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return null;
    }
  }

  Future<bool> activateSemester(
    int semesterId, {
    bool force = false,
    String reason = '',
    String previewRevision = '',
    String? requestId,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/semesters/$semesterId/activate/'),
        body: jsonEncode({
          'preview_revision': previewRevision,
          if (requestId != null) 'request_id': requestId,
          if (force) 'force': true,
          if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        }),
      );

      if (response.statusCode == 200) {
        await fetchPeriods(successMessage: 'Active semester updated.');
        _markDependentDataChanged();
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

  Future<bool> updateSemesterEvaluationSettings(
    int semesterId, {
    bool? peerEvaluationEnabled,
    bool? adviserGradingEnabled,
  }) async {
    if (peerEvaluationEnabled == null && adviserGradingEnabled == null) {
      return false;
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
        Uri.parse('$baseUrl/semesters/$semesterId/'),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        await fetchPeriods(successMessage: 'Evaluation settings updated.');
        _markDependentDataChanged();
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

  void selectSchoolYear(int id) {
    state = state.copyWith(selectedSchoolYearId: id, clearMessage: true);
  }

  void _markDependentDataChanged() {
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.dashboard,
      DataArea.users,
      DataArea.academicRecords,
      DataArea.teams,
      DataArea.grades,
      DataArea.rubrics,
      DataArea.defenseStages,
      DataArea.scheduler,
      DataArea.defenseBoard,
      DataArea.deliverables,
      DataArea.analytics,
      DataArea.audit,
    ]);
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    final schoolYears = _readMapList(payload['school_years']);
    final activeSemester = payload['active_semester'] is Map
        ? Map<String, dynamic>.from(payload['active_semester'])
        : null;
    final selectedSchoolYearId = _resolveSelectedSchoolYear(
      schoolYears,
      activeSemester,
    );

    state = AcademicPeriodState(
      isLoading: false,
      isSaving: false,
      schoolYears: schoolYears,
      activeSemester: activeSemester,
      selectedSchoolYearId: selectedSchoolYearId,
      message: successMessage,
    );
  }

  int? _resolveSelectedSchoolYear(
    List<Map<String, dynamic>> schoolYears,
    Map<String, dynamic>? activeSemester,
  ) {
    final ids = schoolYears.map((year) => _asInt(year['id'])).whereType<int>();
    final idSet = ids.toSet();

    if (state.selectedSchoolYearId != null &&
        idSet.contains(state.selectedSchoolYearId)) {
      return state.selectedSchoolYearId;
    }

    final activeYearId = _asInt(activeSemester?['school_year_id']);
    if (activeYearId != null && idSet.contains(activeYearId)) {
      return activeYearId;
    }

    if (schoolYears.isEmpty) {
      return null;
    }
    return _asInt(schoolYears.first['id']);
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

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
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
