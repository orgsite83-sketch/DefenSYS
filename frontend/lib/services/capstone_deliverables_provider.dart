import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

final capstoneDeliverablesProvider =
    NotifierProvider<CapstoneDeliverablesNotifier, CapstoneDeliverablesState>(
      CapstoneDeliverablesNotifier.new,
    );

class CapstoneDeliverablesState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> teams;
  final List<String> stageOptions;
  final List<Map<String, dynamic>> statuses;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String selectedStage;
  final String search;
  final String status;
  final String? error;
  final String? message;

  const CapstoneDeliverablesState({
    this.isLoading = false,
    this.isSaving = false,
    this.teams = const [],
    this.stageOptions = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.selectedStage = 'Concept Proposal',
    this.search = '',
    this.status = '',
    this.error,
    this.message,
  });

  CapstoneDeliverablesState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? teams,
    List<String>? stageOptions,
    List<Map<String, dynamic>>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? selectedStage,
    String? search,
    String? status,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return CapstoneDeliverablesState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      teams: teams ?? this.teams,
      stageOptions: stageOptions ?? this.stageOptions,
      statuses: statuses ?? this.statuses,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      selectedStage: selectedStage ?? this.selectedStage,
      search: search ?? this.search,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class CapstoneDeliverablesNotifier extends Notifier<CapstoneDeliverablesState> {
  static String get baseUrl => ApiConfig.capstoneDeliverablesUrl;

  @override
  CapstoneDeliverablesState build() {
    return const CapstoneDeliverablesState();
  }

  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextStage = selectedStage ?? state.selectedStage;
    final nextStatus = status ?? state.status;

    state = state.copyWith(
      isLoading: state.teams.isEmpty,
      isSaving: false,
      search: nextSearch,
      selectedStage: nextStage,
      status: nextStatus,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextStage.isNotEmpty) 'stage_label': nextStage,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
        },
      );
      final response = await http.get(uri, headers: await _headers());

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
        );
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

  Future<bool> uploadDeliverable(Map<String, dynamic> payload) async {
    return _postAction(
      'upload',
      payload,
      successMessage: 'Deliverable file metadata saved.',
    );
  }

  Future<bool> removeDeliverable(Map<String, dynamic> payload) async {
    return _postAction(
      'remove',
      payload,
      successMessage: 'Deliverable file removed.',
    );
  }

  Future<bool> endorseTeam(int teamId, String stageLabel) async {
    return _postAction('endorse', {
      'team_id': teamId,
      'stage_label': stageLabel,
    }, successMessage: 'Team endorsed for defense scheduling.');
  }

  Future<bool> _postAction(
    String action,
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$action/'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchDeliverables(successMessage: successMessage);
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
      teams: _readMapList(payload['teams']),
      stageOptions: _readStringList(payload['stage_options']),
      statuses: _readMapList(payload['statuses']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      selectedStage:
          payload['selected_stage']?.toString() ?? state.selectedStage,
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
