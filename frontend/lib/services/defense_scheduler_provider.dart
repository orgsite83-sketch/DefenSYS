import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';

final defenseSchedulerProvider =
    NotifierProvider<DefenseSchedulerNotifier, DefenseSchedulerState>(
      DefenseSchedulerNotifier.new,
    );

class DefenseSchedulerState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> teams;
  final List<Map<String, dynamic>> defenseStages;
  final List<Map<String, dynamic>> rubrics;
  final List<Map<String, dynamic>> peerRubrics;
  final List<Map<String, dynamic>> panelists;
  final List<Map<String, dynamic>> generatedSlots;
  final List<String> statuses;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String search;
  final String scope;
  final String status;
  final String? error;
  final String? message;

  const DefenseSchedulerState({
    this.isLoading = false,
    this.isSaving = false,
    this.schedules = const [],
    this.teams = const [],
    this.defenseStages = const [],
    this.rubrics = const [],
    this.peerRubrics = const [],
    this.panelists = const [],
    this.generatedSlots = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.scope = '',
    this.status = '',
    this.error,
    this.message,
  });

  DefenseSchedulerState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? schedules,
    List<Map<String, dynamic>>? teams,
    List<Map<String, dynamic>>? defenseStages,
    List<Map<String, dynamic>>? rubrics,
    List<Map<String, dynamic>>? peerRubrics,
    List<Map<String, dynamic>>? panelists,
    List<Map<String, dynamic>>? generatedSlots,
    List<String>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? scope,
    String? status,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return DefenseSchedulerState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      schedules: schedules ?? this.schedules,
      teams: teams ?? this.teams,
      defenseStages: defenseStages ?? this.defenseStages,
      rubrics: rubrics ?? this.rubrics,
      peerRubrics: peerRubrics ?? this.peerRubrics,
      panelists: panelists ?? this.panelists,
      generatedSlots: generatedSlots ?? this.generatedSlots,
      statuses: statuses ?? this.statuses,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      search: search ?? this.search,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class DefenseSchedulerNotifier extends Notifier<DefenseSchedulerState> {
    static String get baseUrl => ApiConfig.defenseSchedulesUrl;

  @override
  DefenseSchedulerState build() {
    return const DefenseSchedulerState();
  }

  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextScope = scope ?? state.scope;
    final nextStatus = status ?? state.status;

    state = state.copyWith(
      isLoading: state.schedules.isEmpty,
      isSaving: false,
      search: nextSearch,
      scope: nextScope,
      status: nextStatus,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextScope.isNotEmpty) 'scope': nextScope,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
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

  Future<bool> generatePlan(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      generatedSlots: const [],
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/generate-plan/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isSaving: false,
          generatedSlots: _readMapList(data['slots']),
          teams: _readMapList(data['teams']),
          defenseStages: _readMapList(data['defense_stages']),
          rubrics: _readMapList(data['rubrics']),
          peerRubrics: _readMapList(data['peer_rubrics']),
          panelists: _readMapList(data['panelists']),
          activeSemester: data['active_semester'] is Map
              ? Map<String, dynamic>.from(data['active_semester'])
              : state.activeSemester,
          message: '${data['slot_count'] ?? 0} schedule slots generated.',
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

  Future<bool> confirmPlan(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/confirm-plan/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = data['created_count'] ?? 0;
        _applyPayload(data, successMessage: '$created schedules saved.');
        state = state.copyWith(generatedSlots: const []);
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

  Future<bool> createSchedule(Map<String, dynamic> payload) async {
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
        await fetchSchedules(successMessage: 'Schedule saved.');
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

  Future<bool> updateStatus(int scheduleId, String status) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$scheduleId/'),
        
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode == 200) {
        await fetchSchedules(successMessage: 'Schedule status updated.');
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

  Future<Map<String, dynamic>?> fetchPitEventConfig({
    required String eventName,
    int? semesterId,
  }) async {
    final trimmed = eventName.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse('$baseUrl/pit-event-config/').replace(
        queryParameters: {
          'event_name': trimmed,
          if (semesterId != null) 'semester_id': semesterId.toString(),
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return null;
      }
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final config = data['config'];
      if (config is Map) {
        return Map<String, dynamic>.from(config);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteSchedule(int scheduleId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$scheduleId/'),
        
      );

      if (response.statusCode == 200) {
        await fetchSchedules(successMessage: 'Schedule deleted.');
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
      schedules: _readMapList(payload['schedules']),
      teams: _readMapList(payload['teams']),
      defenseStages: _readMapList(payload['defense_stages']),
      rubrics: _readMapList(payload['rubrics']),
      peerRubrics: _readMapList(payload['peer_rubrics']),
      panelists: _readMapList(payload['panelists']),
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
