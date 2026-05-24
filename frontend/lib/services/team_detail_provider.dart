import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_http.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final teamDetailProvider =
    NotifierProvider.family<TeamDetailNotifier, TeamDetailState, int>(
      TeamDetailNotifier.new,
    );

class TeamDetailState {
  final bool isLoading;
  final bool isSaving;
  final Map<String, dynamic>? team;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> advisers;
  final List<String> statuses;
  final List<Map<String, dynamic>> adviserHistory;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> weeklyReports;
  final Map<String, dynamic>? deliverableTeam;
  final List<String> stageOptions;
  final String? error;
  final String? message;

  const TeamDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.team,
    this.students = const [],
    this.advisers = const [],
    this.statuses = const [],
    this.adviserHistory = const [],
    this.documents = const [],
    this.weeklyReports = const [],
    this.deliverableTeam,
    this.stageOptions = const [],
    this.error,
    this.message,
  });

  TeamDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    Map<String, dynamic>? team,
    List<Map<String, dynamic>>? students,
    List<Map<String, dynamic>>? advisers,
    List<String>? statuses,
    List<Map<String, dynamic>>? adviserHistory,
    List<Map<String, dynamic>>? documents,
    List<Map<String, dynamic>>? weeklyReports,
    Map<String, dynamic>? deliverableTeam,
    List<String>? stageOptions,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    bool clearDeliverableTeam = false,
  }) {
    return TeamDetailState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      team: team ?? this.team,
      students: students ?? this.students,
      advisers: advisers ?? this.advisers,
      statuses: statuses ?? this.statuses,
      adviserHistory: adviserHistory ?? this.adviserHistory,
      documents: documents ?? this.documents,
      weeklyReports: weeklyReports ?? this.weeklyReports,
      deliverableTeam: clearDeliverableTeam
          ? null
          : deliverableTeam ?? this.deliverableTeam,
      stageOptions: stageOptions ?? this.stageOptions,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class TeamDetailNotifier extends Notifier<TeamDetailState> {
  TeamDetailNotifier(this._teamId);

  final int _teamId;

  @override
  TeamDetailState build() {
    return const TeamDetailState();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);

    try {
      final teamResponse = await _client.get(
        Uri.parse('${ApiConfig.teamsUrl}/$_teamId/'),
      );

      if (teamResponse.statusCode != 200) {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(teamResponse),
        );
        return;
      }

      final teamPayload = Map<String, dynamic>.from(
        jsonDecode(teamResponse.body),
      );
      final team = Map<String, dynamic>.from(
        teamPayload['team'] as Map? ?? const {},
      );
      final students = _readMapList(teamPayload['students']);
      final advisers = _readMapList(teamPayload['advisers']);
      final statuses = (teamPayload['statuses'] as List? ?? const [])
          .map((item) => item.toString())
          .toList();

      final level = team['level']?.toString() ?? '';
      final isCapstone = level.toUpperCase().contains('CAPSTONE');

      List<Map<String, dynamic>> adviserHistory = const [];
      if (isCapstone) {
        adviserHistory = await _fetchAdviserHistory();
      }

      final documents = await _fetchDocuments();
      final weeklyReports = await _fetchWeeklyReports();
      final deliverableData = await _fetchDeliverableTeam();

      state = state.copyWith(
        isLoading: false,
        team: team,
        students: students,
        advisers: advisers,
        statuses: statuses,
        adviserHistory: adviserHistory,
        documents: documents,
        weeklyReports: weeklyReports,
        deliverableTeam: deliverableData.$1,
        stageOptions: deliverableData.$2,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> save(Map<String, dynamic> payload) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);

    try {
      final response = await _client.patch(
        Uri.parse('${ApiConfig.teamsUrl}/$_teamId/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final team = Map<String, dynamic>.from(data['team'] as Map? ?? const {});
        final level = team['level']?.toString() ?? '';
        var adviserHistory = state.adviserHistory;
        if (level.toUpperCase().contains('CAPSTONE')) {
          adviserHistory = await _fetchAdviserHistory();
        }
        state = state.copyWith(
          isSaving: false,
          team: team,
          adviserHistory: adviserHistory,
          message: 'Team updated.',
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Connection error: $e',
      );
      return false;
    }
  }

  Future<void> refreshDocuments() async {
    try {
      final documents = await _fetchDocuments();
      state = state.copyWith(documents: documents);
    } catch (_) {
      // Keep existing list on failure.
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAdviserHistory() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.teamsUrl}/$_teamId/adviser-history/'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return _readMapList(payload['assignments']);
      }
    } catch (_) {
      // Empty on failure.
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _fetchDocuments() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.teamDocumentsUrl}/?team_id=$_teamId'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return _readMapList(payload['documents']);
      }
    } catch (_) {
      // Empty on failure.
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _fetchWeeklyReports() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.weeklyProgressUrl}/?team_id=$_teamId'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return _readMapList(payload['reports']);
      }
    } catch (_) {
      // Empty on failure.
    }
    return const [];
  }

  Future<(Map<String, dynamic>?, List<String>)> _fetchDeliverableTeam() async {
    try {
      final response = await _client.get(
        Uri.parse(ApiConfig.capstoneDeliverablesUrl),
      );
      if (response.statusCode != 200) {
        return (null, <String>[]);
      }
      final payload = Map<String, dynamic>.from(jsonDecode(response.body));
      final teams = _readMapList(payload['teams']);
      final stageOptions = List<String>.from(
        (payload['stage_options'] as List? ?? const [])
            .map((item) => item.toString()),
      );
      for (final team in teams) {
        if (_asInt(team['id']) == _teamId) {
          return (team, stageOptions);
        }
      }
      return (null, stageOptions);
    } catch (_) {
      return (null, <String>[]);
    }
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return const [];
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
        if (data['error'] != null) {
          return data['error'].toString();
        }
        final errors = <String>[];
        data.forEach((key, value) {
          if (value is List) {
            errors.add('$key: ${value.join(', ')}');
          } else {
            errors.add('$key: $value');
          }
        });
        if (errors.isNotEmpty) {
          return errors.join('\n');
        }
      }
    } catch (_) {
      // Fall through.
    }
    return 'Request failed (${response.statusCode})';
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
