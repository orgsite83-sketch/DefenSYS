import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

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
    this.search = '',
    this.level = 'Capstone',
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
        },
      );
      final response = await http.get(uri, headers: await _headers());

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
      final response = await http.post(
        Uri.parse('$baseUrl/'),
        headers: await _headers(),
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
      final response = await http.patch(
        Uri.parse('$baseUrl/$teamId/'),
        headers: await _headers(),
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
      final response = await http.delete(
        Uri.parse('$baseUrl/$teamId/'),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        await fetchTeams(successMessage: 'Team deleted.');
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

  Future<bool> bulkImport(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      state = state.copyWith(error: 'CSV has no valid team rows.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/bulk-import/'),
        headers: await _headers(),
        body: jsonEncode({'teams': rows}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        await fetchTeams(
          successMessage: '$created teams imported. $errors row errors.',
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
