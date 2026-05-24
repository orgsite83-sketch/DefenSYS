import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'provider_errors.dart';
import 'session_expired.dart';

final defenseBoardProvider =
    NotifierProvider<DefenseBoardNotifier, DefenseBoardState>(
      DefenseBoardNotifier.new,
    );

class DefenseBoardState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> schedules;
  final List<String> stageOptions;
  final List<String> statuses;
  final List<Map<String, dynamic>> scopes;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String search;
  final String stage;
  final String status;
  final String scope;
  final String? error;
  final String? message;

  const DefenseBoardState({
    this.isLoading = false,
    this.isSaving = false,
    this.schedules = const [],
    this.stageOptions = const [],
    this.statuses = const [],
    this.scopes = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.stage = '',
    this.status = '',
    this.scope = '',
    this.error,
    this.message,
  });

  DefenseBoardState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? schedules,
    List<String>? stageOptions,
    List<String>? statuses,
    List<Map<String, dynamic>>? scopes,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return DefenseBoardState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      schedules: schedules ?? this.schedules,
      stageOptions: stageOptions ?? this.stageOptions,
      statuses: statuses ?? this.statuses,
      scopes: scopes ?? this.scopes,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      search: search ?? this.search,
      stage: stage ?? this.stage,
      status: status ?? this.status,
      scope: scope ?? this.scope,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class DefenseBoardNotifier extends Notifier<DefenseBoardState> {
    static String get baseUrl => ApiConfig.defenseBoardUrl;

  @override
  DefenseBoardState build() {
    return const DefenseBoardState();
  }

  Future<void> fetchBoard({
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextStage = stage ?? state.stage;
    final nextStatus = status ?? state.status;
    final nextScope = scope ?? state.scope;

    state = state.copyWith(
      isLoading: state.schedules.isEmpty,
      isSaving: false,
      search: nextSearch,
      stage: nextStage,
      status: nextStatus,
      scope: nextScope,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextStage.isNotEmpty) 'stage': nextStage,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          if (nextScope.isNotEmpty) 'scope': nextScope,
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
        await fetchBoard(successMessage: 'Schedule status updated.');
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
        await fetchBoard(successMessage: 'Schedule entry removed.');
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
      stageOptions: _readStringList(payload['stage_options']),
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
