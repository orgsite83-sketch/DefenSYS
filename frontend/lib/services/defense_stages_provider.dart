import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final defenseStagesProvider =
    NotifierProvider<DefenseStagesNotifier, DefenseStagesState>(
      DefenseStagesNotifier.new,
    );

class DefenseStagesState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> stages;
  final List<Map<String, dynamic>> activeStages;
  final Map<String, dynamic> counts;
  final String? error;
  final String? message;

  const DefenseStagesState({
    this.isLoading = false,
    this.isSaving = false,
    this.stages = const [],
    this.activeStages = const [],
    this.counts = const {},
    this.error,
    this.message,
  });

  DefenseStagesState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? stages,
    List<Map<String, dynamic>>? activeStages,
    Map<String, dynamic>? counts,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return DefenseStagesState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      stages: stages ?? this.stages,
      activeStages: activeStages ?? this.activeStages,
      counts: counts ?? this.counts,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class DefenseStagesNotifier extends Notifier<DefenseStagesState> {
    static String get baseUrl => ApiConfig.defenseStagesUrl;

  @override
  DefenseStagesState build() {
    return const DefenseStagesState();
  }

  Future<void> fetchStages({String? successMessage}) async {
    state = state.copyWith(
      isLoading: state.stages.isEmpty,
      isSaving: false,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/'),
        
      );

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

  Future<bool> addStage(Map<String, dynamic> payload) async {
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
        await fetchStages(successMessage: 'Defense stage added.');
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

  Future<bool> updateStage(int stageId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$stageId/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchStages(successMessage: 'Defense stage updated.');
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

  Future<Map<String, dynamic>?> fetchStageDetail(
    int stageId, {
    int? semesterId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/$stageId/').replace(
        queryParameters:
            semesterId != null ? {'semester_id': '$semesterId'} : null,
      );
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      state = state.copyWith(error: _errorFromResponse(response));
    } catch (e) {
      state = state.copyWith(error: 'Connection error: $e');
    }
    return null;
  }

  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$stageId/grading-config/?semester_id=$semesterId'),
        
        body: jsonEncode(weights),
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          message: 'Grade weights updated.',
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

  Future<bool> deleteStage(int stageId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$stageId/'),
        
      );

      if (response.statusCode == 200) {
        await fetchStages(successMessage: 'Defense stage deleted.');
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
      stages: _readMapList(payload['stages']),
      activeStages: _readMapList(payload['active_stages']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
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
