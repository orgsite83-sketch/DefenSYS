import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/data_refresh_provider.dart';

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
  final List<Map<String, dynamic>> pitEvents;
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
  final String termContext;
  final String? error;
  final String? message;
  final Map<int, Map<String, String>> criterionErrors;

  const RubricEngineState({
    this.isLoading = false,
    this.isSaving = false,
    this.rubrics = const [],
    this.semesters = const [],
    this.defenseStages = const [],
    this.pitEvents = const [],
    this.scopes = const [],
    this.scaleOptions = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.scope = 'capstone',
    this.status = '',
    this.evaluationType = '',
    this.termContext = '',
    this.error,
    this.message,
    this.criterionErrors = const {},
  });

  RubricEngineState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? rubrics,
    List<Map<String, dynamic>>? semesters,
    List<Map<String, dynamic>>? defenseStages,
    List<Map<String, dynamic>>? pitEvents,
    List<Map<String, dynamic>>? scopes,
    List<String>? scaleOptions,
    List<String>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
    Map<int, Map<String, String>>? criterionErrors,
  }) {
    return RubricEngineState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      rubrics: rubrics ?? this.rubrics,
      semesters: semesters ?? this.semesters,
      defenseStages: defenseStages ?? this.defenseStages,
      pitEvents: pitEvents ?? this.pitEvents,
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
      termContext: termContext ?? this.termContext,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
      criterionErrors: clearError
          ? const {}
          : criterionErrors ?? this.criterionErrors,
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
    String? termContext,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextScope = scope ?? (state.scope.isEmpty ? 'capstone' : state.scope);
    final nextStatus = status ?? state.status;
    final nextEvaluationType = evaluationType ?? state.evaluationType;
    final nextTermContext = termContext ?? state.termContext;

    state = state.copyWith(
      isLoading: state.rubrics.isEmpty,
      isSaving: false,
      search: nextSearch,
      scope: nextScope,
      status: nextStatus,
      evaluationType: nextEvaluationType,
      termContext: nextTermContext,
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
          if (nextTermContext.isNotEmpty) 'term_context': nextTermContext,
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

  Future<Map<String, dynamic>?> fetchSingleRubric(int rubricId) async {
    try {
      final uri = Uri.parse('$baseUrl/$rubricId/');
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        if (payload['rubric'] != null) {
          final rubric = Map<String, dynamic>.from(payload['rubric']);
          final list = List<Map<String, dynamic>>.from(state.rubrics);
          final idx = list.indexWhere((r) => r['id'] == rubric['id']);
          if (idx >= 0) {
            list[idx] = rubric;
          } else {
            list.insert(0, rubric);
          }
          state = state.copyWith(
            rubrics: list,
            semesters: payload['semesters'] != null
                ? _readMapList(payload['semesters'])
                : state.semesters,
            defenseStages: payload['defense_stages'] != null
                ? _readMapList(payload['defense_stages'])
                : state.defenseStages,
          );
          return rubric;
        }
      }
    } catch (_) {}
    return null;
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
        _markDependentDataChanged();
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response, payload: payload),
        criterionErrors: _criterionErrorsFromResponse(response),
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
        _markDependentDataChanged();
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response, payload: payload),
        criterionErrors: _criterionErrorsFromResponse(response),
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
      final response = await _client.delete(Uri.parse('$baseUrl/$rubricId/'));

      if (response.statusCode == 200) {
        await fetchRubrics(successMessage: 'Rubric deleted.');
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

  void _markDependentDataChanged() {
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.grades,
      DataArea.defenseStages,
      DataArea.scheduler,
      DataArea.defenseBoard,
      DataArea.audit,
    ]);
  }

  /// Copy sources span semesters without changing the directory's filters/data.
  Future<List<Map<String, dynamic>>> checkExistingRubrics({
    String? scope,
  }) async {
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {if (scope != null && scope.isNotEmpty) 'scope': scope},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(_errorFromResponse(response));
    }
    final payload = Map<String, dynamic>.from(jsonDecode(response.body));
    return _readMapList(payload['rubrics']);
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      rubrics: _readMapList(payload['rubrics']),
      semesters: _readMapList(payload['semesters']),
      defenseStages: _readMapList(payload['defense_stages']),
      pitEvents: _readMapList(payload['pit_events']),
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

  String? _validationText(dynamic value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is List) {
      for (final item in value) {
        final text = _validationText(item);
        if (text != null) return text;
      }
    }
    if (value is Map) {
      for (final item in value.entries) {
        final text = _validationText(item.value);
        if (text != null) {
          return '${item.key.toString().replaceAll('_', ' ')}: $text';
        }
      }
    }
    return null;
  }

  Map<int, Map<String, String>> _criterionErrorsFromResponse(
    http.Response response,
  ) {
    try {
      final data = jsonDecode(response.body);
      if (data is! Map) return {};
      final errors = data['criteria'];
      final entries = errors is List
          ? errors.asMap().entries
          : errors is Map
          ? errors.entries
          : const <MapEntry<dynamic, dynamic>>[];
      final result = <int, Map<String, String>>{};
      for (final entry in entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null || entry.value is! Map) {
          continue;
        }
        final fields = <String, String>{};
        for (final field in (entry.value as Map).entries) {
          final text = _validationText(field.value);
          if (text != null) fields[field.key.toString()] = text;
        }
        if (fields.isNotEmpty) result[index] = fields;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  String _errorFromResponse(
    http.Response response, {
    Map<String, dynamic>? payload,
  }) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final detail = _validationText(data['detail']);
        if (detail != null) return detail;
        final errors = _criterionErrorsFromResponse(response);
        if (errors.isNotEmpty) {
          final entry = errors.entries.first;
          final criteria = payload?['criteria'];
          var label = 'Criterion ${entry.key + 1}';
          if (criteria is List &&
              entry.key >= 0 &&
              entry.key < criteria.length) {
            final criterion = criteria[entry.key];
            final section = criterion is Map
                ? criterion['section']?.toString() ?? ''
                : '';
            if (section.isNotEmpty) {
              final localIndex = criteria
                  .take(entry.key + 1)
                  .where((item) => item is Map && item['section'] == section)
                  .length;
              label = 'Section "$section", criterion $localIndex';
            }
          }
          final field = entry.value.entries.first;
          return '$label — ${field.key.replaceAll('_', ' ')}: ${field.value}';
        }
        return _validationText(data) ?? 'Rubric could not be saved.';
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }

    return 'Request failed. Status: ${response.statusCode}';
  }
}
