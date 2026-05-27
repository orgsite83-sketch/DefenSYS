import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';

final studentTeamsProvider =
    NotifierProvider<StudentTeamsNotifier, StudentTeamsState>(
      StudentTeamsNotifier.new,
    );

class StudentTeamsState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> teams;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> advisers;
  final List<String> levels;
  final List<String> statuses;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String capstoneMode;
  final bool canCreateCapstoneTeams;
  final String? capstoneModeMessage;
  final String operatingMode;
  final String? operatingMessage;
  final String search;
  final String level;
  final String status;
  final String? error;
  final String? message;

  const StudentTeamsState({
    this.isLoading = false,
    this.isSaving = false,
    this.teams = const [],
    this.students = const [],
    this.advisers = const [],
    this.levels = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.capstoneMode = 'off',
    this.canCreateCapstoneTeams = false,
    this.capstoneModeMessage,
    this.operatingMode = 'active',
    this.operatingMessage,
    this.search = '',
    this.level = '',
    this.status = '',
    this.error,
    this.message,
  });

  StudentTeamsState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? teams,
    List<Map<String, dynamic>>? students,
    List<Map<String, dynamic>>? advisers,
    List<String>? levels,
    List<String>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? capstoneMode,
    bool? canCreateCapstoneTeams,
    String? capstoneModeMessage,
    String? operatingMode,
    String? operatingMessage,
    String? search,
    String? level,
    String? status,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    bool clearActiveSemester = false,
  }) {
    return StudentTeamsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      teams: teams ?? this.teams,
      students: students ?? this.students,
      advisers: advisers ?? this.advisers,
      levels: levels ?? this.levels,
      statuses: statuses ?? this.statuses,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      capstoneMode: capstoneMode ?? this.capstoneMode,
      canCreateCapstoneTeams:
          canCreateCapstoneTeams ?? this.canCreateCapstoneTeams,
      capstoneModeMessage: capstoneModeMessage ?? this.capstoneModeMessage,
      operatingMode: operatingMode ?? this.operatingMode,
      operatingMessage: operatingMessage ?? this.operatingMessage,
      search: search ?? this.search,
      level: level ?? this.level,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class StudentTeamsNotifier extends Notifier<StudentTeamsState> {
    static String get baseUrl => ApiConfig.teamsUrl;

  @override
  StudentTeamsState build() {
    return const StudentTeamsState();
  }

  Future<void> fetchTeams({
    String? search,
    String? level,
    String? status,
    String? scope,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextLevel = level ?? state.level;
    final nextStatus = status ?? state.status;

    state = state.copyWith(
      isLoading: state.teams.isEmpty,
      isSaving: false,
      search: nextSearch,
      level: nextLevel,
      status: nextStatus,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextLevel.isNotEmpty) 'level': nextLevel,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          if (scope != null && scope.isNotEmpty) 'scope': scope,
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

  Future<bool> addTeam(Map<String, dynamic> payload) async {
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
        await fetchTeams(successMessage: 'Team created.');
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

  Future<bool> updateTeam(int teamId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$teamId/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchTeams(successMessage: 'Team updated.');
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

  Future<bool> deleteTeam(int teamId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$teamId/'),
        
      );

      if (response.statusCode == 200) {
        await fetchTeams(successMessage: 'Team deleted.');
        return true;
      }

      if (response.statusCode == 409) {
        final data = jsonDecode(response.body);
        final warning = data is Map ? data['warning']?.toString() : null;
        state = state.copyWith(
          isSaving: false,
          error: warning ?? 'This team cannot be deleted.',
        );
        return false;
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


  Future<Map<String, dynamic>?> bulkImportPreview(
    List<Map<String, dynamic>> rows, {
    String adviserFilter = 'all',
  }) async {
    if (rows.isEmpty) {
      state = state.copyWith(error: 'CSV has no valid team rows.');
      return null;
    }

    state = state.copyWith(clearError: true, clearMessage: true);

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/bulk-import/preview/'),
        
        body: jsonEncode({
          'teams': rows,
          'adviser_filter': adviserFilter,
        }),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      state = state.copyWith(error: _errorFromResponse(response));
      return null;
    } catch (e) {
      state = state.copyWith(error: 'Connection error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> bulkImport(
    List<Map<String, dynamic>> rows, {
    String adviserFilter = 'all',
  }) async {
    if (rows.isEmpty) {
      state = state.copyWith(error: 'CSV has no valid team rows.');
      return null;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/bulk-import/'),
        
        body: jsonEncode({
          'teams': rows,
          'adviser_filter': adviserFilter,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        await fetchTeams(
          successMessage: '$created teams imported. $errors row errors.',
        );
        return payload;
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

  Future<List<Map<String, dynamic>>> fetchAdviserHistory(int teamId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/$teamId/adviser-history/'),
        
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (payload['assignments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {
      // Caller shows empty state on failure.
    }
    return const [];
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      teams: _readMapList(payload['teams']),
      students: _readMapList(payload['students']),
      advisers: _readMapList(payload['advisers']),
      levels: _readStringList(payload['levels']),
      statuses: _readStringList(payload['statuses']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      capstoneMode: payload['capstone_mode']?.toString() ?? state.capstoneMode,
      canCreateCapstoneTeams: payload['can_create_capstone_teams'] == true,
      capstoneModeMessage: payload['capstone_mode_message']?.toString(),
      operatingMode: payload['operating_mode']?.toString() ?? 'active',
      operatingMessage: payload['operating_message']?.toString(),
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
