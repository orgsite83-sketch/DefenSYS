import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

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
  final List<Map<String, dynamic>> grades;
  final String? gradesError;
  final List<Map<String, dynamic>> events;
  final String? selectedEvent;
  final String? legacyError;
  final String? deliverablesError;

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
    this.grades = const [],
    this.gradesError,
    this.events = const [],
    this.selectedEvent,
    this.legacyError,
    this.deliverablesError,
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
    List<Map<String, dynamic>>? grades,
    String? gradesError,
    bool clearGradesError = false,
    List<Map<String, dynamic>>? events,
    String? selectedEvent,
    String? legacyError,
    String? deliverablesError,
    bool clearSectionErrors = false,
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
      grades: grades ?? this.grades,
      gradesError: clearGradesError ? null : gradesError ?? this.gradesError,
      events: events ?? this.events,
      selectedEvent: selectedEvent ?? this.selectedEvent,
      legacyError: clearSectionErrors
          ? legacyError
          : legacyError ?? this.legacyError,
      deliverablesError: clearSectionErrors
          ? deliverablesError
          : deliverablesError ?? this.deliverablesError,
    );
  }
}

class TeamDetailNotifier extends Notifier<TeamDetailState> {
  TeamDetailNotifier(this._teamId);

  final int _teamId;
  int _generation = 0;
  String? _eventName;

  Future<void> selectEvent(String eventName) {
    _eventName = eventName;
    return load();
  }

  @override
  TeamDetailState build() {
    return const TeamDetailState();
  }

  Future<void> load() async {
    final ticket = ++_generation;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearMessage: true,
      clearGradesError: true,
    );

    try {
      final teamResponse = await _client.get(
        Uri.parse('${ApiConfig.teamsUrl}/$_teamId/').replace(
          queryParameters: {if (_eventName != null) 'event_name': _eventName!},
        ),
      );
      if (!ref.mounted || ticket != _generation) return;

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
      final selectedEvent = teamPayload['selected_event_name']?.toString();
      if (!isCapstone) _eventName = selectedEvent;
      state = state.copyWith(
        team: team,
        students: students,
        advisers: advisers,
        statuses: statuses,
        events: _readMapList(teamPayload['team_events']),
        selectedEvent: selectedEvent,
      );

      // These reads depend only on the team identity, not on each other.
      final historyFuture = isCapstone
          ? _fetchAdviserHistory()
          : Future.value(<Map<String, dynamic>>[]);
      final documentsFuture = teamPayload['legacy_documents_count'] == 0
          ? Future.value((<Map<String, dynamic>>[], null as String?))
          : _fetchDocuments();
      final weeklyReportsFuture =
          isCapstone && teamPayload['legacy_reports_count'] != 0
          ? _fetchWeeklyReports()
          : Future.value((<Map<String, dynamic>>[], null as String?));
      final deliverablesFuture = _fetchDeliverableTeam(isCapstone);
      final gradesFuture = _fetchGrades(isCapstone ? 'capstone' : 'pit');

      final adviserHistory = await historyFuture;
      final documents = await documentsFuture;
      final weeklyReports = await weeklyReportsFuture;
      final deliverableData = await deliverablesFuture;
      final grades = await gradesFuture;
      if (!ref.mounted || ticket != _generation) return;

      state = state.copyWith(
        isLoading: false,
        team: team,
        students: students,
        advisers: advisers,
        statuses: statuses,
        adviserHistory: adviserHistory,
        documents: documents.$2 == null ? documents.$1 : state.documents,
        weeklyReports: weeklyReports.$2 == null
            ? weeklyReports.$1
            : state.weeklyReports,
        deliverableTeam: deliverableData.$1,
        stageOptions: deliverableData.$2,
        grades: grades.$1,
        gradesError: grades.$2,
        legacyError: documents.$2 ?? weeklyReports.$2,
        deliverablesError: deliverableData.$3,
        clearSectionErrors: true,
      );
    } catch (e) {
      if (!ref.mounted || ticket != _generation) return;
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  Future<bool> save(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('${ApiConfig.teamsUrl}/$_teamId/'),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final team = Map<String, dynamic>.from(
          data['team'] as Map? ?? const {},
        );
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
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<void> refreshDocuments() async {
    try {
      final documents = await _fetchDocuments();
      if (!ref.mounted) return;
      state = state.copyWith(
        documents: documents.$1,
        legacyError: documents.$2,
        clearSectionErrors: true,
        deliverablesError: state.deliverablesError,
      );
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

  Future<(List<Map<String, dynamic>>, String?)> _fetchDocuments() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.teamDocumentsUrl}/?team_id=$_teamId'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (_readMapList(payload['documents']), null);
      }
    } catch (_) {
      // Empty on failure.
    }
    return (
      const <Map<String, dynamic>>[],
      'Legacy documents could not be loaded. Please try again.',
    );
  }

  Future<(List<Map<String, dynamic>>, String?)> _fetchWeeklyReports() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.weeklyProgressUrl}/?team_id=$_teamId&legacy=1'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (_readMapList(payload['reports']), null);
      }
    } catch (_) {
      // Empty on failure.
    }
    return (
      const <Map<String, dynamic>>[],
      'Legacy reports could not be loaded. Please try again.',
    );
  }

  Future<(List<Map<String, dynamic>>, String?)> _fetchGrades(
    String scope,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse(
          '${ApiConfig.gradeCenterUrl}/',
        ).replace(queryParameters: {'team_id': '$_teamId', 'scope': scope}),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (_readMapList(payload['grades']), null);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return (
          const <Map<String, dynamic>>[],
          'You do not have permission to view this team\'s grades.',
        );
      }
    } catch (_) {
      // A failed read must not look like a team with no evaluations.
    }
    return (
      const <Map<String, dynamic>>[],
      'Grades could not be loaded. Please try again.',
    );
  }

  Future<(Map<String, dynamic>?, List<String>, String?)> _fetchDeliverableTeam(
    bool isCapstone,
  ) async {
    try {
      final scope = isCapstone ? 'capstone' : 'pit';
      final uri = Uri.parse(ApiConfig.capstoneDeliverablesUrl).replace(
        queryParameters: {'scope': scope, 'team_id': _teamId.toString()},
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return (
          null,
          <String>[],
          'Deliverables could not be loaded. Please try again.',
        );
      }
      final payload = Map<String, dynamic>.from(jsonDecode(response.body));
      final teams = _readMapList(payload['teams']);
      final stageOptions = _readStringList(payload['stage_options']);
      for (final team in teams) {
        if (_asInt(team['id']) == _teamId) {
          final teamStages = _readMapList(team['stages'])
              .map((s) => s['stage_label']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          final effectiveStageOptions = teamStages.isNotEmpty
              ? teamStages
              : stageOptions;
          return (team, effectiveStageOptions, null);
        }
      }
      return (null, stageOptions, null);
    } catch (_) {
      return (
        null,
        <String>[],
        'Deliverables could not be loaded. Please try again.',
      );
    }
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isEmpty) {
        continue;
      }
      if (seen.add(text)) {
        result.add(text);
      }
    }
    return result;
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
