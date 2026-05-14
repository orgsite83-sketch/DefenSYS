import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

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
      final response = await http.get(
        Uri.parse('$baseUrl/'),
        headers: await _headers(),
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
      final response = await http.post(
        Uri.parse('$baseUrl/'),
        headers: await _headers(),
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
      final response = await http.patch(
        Uri.parse('$baseUrl/$stageId/'),
        headers: await _headers(),
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

  Future<bool> deleteStage(int stageId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/$stageId/'),
        headers: await _headers(),
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
