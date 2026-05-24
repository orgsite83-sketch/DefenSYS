import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final rubricEngineProvider =
    NotifierProvider<RubricEngineNotifier, RubricEngineState>(
      RubricEngineNotifier.new,
    );

class RubricEngineState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> rubrics;
  final List<Map<String, dynamic>> semesters;
  final List<Map<String, dynamic>> defenseStages;
  final List<Map<String, dynamic>> scopes;
  final List<String> scaleOptions;
  final List<String> statuses;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String search;
  final String scope;
  final String status;
  /// API query `evaluation_type`; empty means no filter (show all types).
  final String evaluationType;
  final String? error;
  final String? message;

  const RubricEngineState({
    this.isLoading = false,
    this.isSaving = false,
    this.rubrics = const [],
    this.semesters = const [],
    this.defenseStages = const [],
    this.scopes = const [],
    this.scaleOptions = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.scope = '',
    this.status = '',
    this.evaluationType = '',
    this.error,
    this.message,
  });

  RubricEngineState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? rubrics,
    List<Map<String, dynamic>>? semesters,
    List<Map<String, dynamic>>? defenseStages,
    List<Map<String, dynamic>>? scopes,
    List<String>? scaleOptions,
    List<String>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return RubricEngineState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      rubrics: rubrics ?? this.rubrics,
      semesters: semesters ?? this.semesters,
      defenseStages: defenseStages ?? this.defenseStages,
      scopes: scopes ?? this.scopes,
      scaleOptions: scaleOptions ?? this.scaleOptions,
      statuses: statuses ?? this.statuses,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      search: search ?? this.search,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      evaluationType: evaluationType ?? this.evaluationType,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class RubricEngineNotifier extends Notifier<RubricEngineState> {
    static String get baseUrl => ApiConfig.rubricsUrl;

  @override
  RubricEngineState build() {
    return const RubricEngineState();
  }

  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextScope = scope ?? state.scope;
    final nextStatus = status ?? state.status;
    final nextEvaluationType = evaluationType ?? state.evaluationType;

    state = state.copyWith(
      isLoading: state.rubrics.isEmpty,
      isSaving: false,
      search: nextSearch,
      scope: nextScope,
      status: nextStatus,
      evaluationType: nextEvaluationType,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextScope.isNotEmpty) 'scope': nextScope,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          if (nextEvaluationType.isNotEmpty)
            'evaluation_type': nextEvaluationType,
        },
      );
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

  Future<bool> addRubric(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        await fetchRubrics(successMessage: 'Rubric saved.');
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

  Future<bool> updateRubric(int rubricId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$rubricId/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric updated.');
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

  Future<bool> deleteRubric(int rubricId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$rubricId/'),
        
      );

      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric deleted.');
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

  Future<bool> publishRubric(int rubricId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/$rubricId/publish/'),
        
      );

      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric published and locked.');
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

  Future<bool> updateWeights(int rubricId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$rubricId/weights/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Weight configuration saved.');
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
      rubrics: _readMapList(payload['rubrics']),
      semesters: _readMapList(payload['semesters']),
      defenseStages: _readMapList(payload['defense_stages']),
      scopes: _readMapList(payload['scopes']),
      scaleOptions: _readStringList(payload['scale_options']),
      statuses: _readStringList(payload['statuses']),
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
