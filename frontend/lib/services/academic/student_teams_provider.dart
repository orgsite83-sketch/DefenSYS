import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/data_refresh_provider.dart';
import '../auth/auth_provider.dart';

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
  final String workspace;
  final String? yearLevel;
  final String? section;
  final String? eventName;
  final List<Map<String, dynamic>> pitEvents;
  final List<Map<String, dynamic>> rosterContext;
  final Map<String, dynamic> capstoneHistory;
  final String historyIntake, historyPhase, historyStage;
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
    this.workspace = '',
    this.yearLevel,
    this.section,
    this.eventName,
    this.pitEvents = const [],
    this.rosterContext = const [],
    this.capstoneHistory = const {},
    this.historyIntake = '',
    this.historyPhase = '',
    this.historyStage = '',
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
    String? workspace,
    String? yearLevel,
    String? section,
    String? eventName,
    List<Map<String, dynamic>>? pitEvents,
    List<Map<String, dynamic>>? rosterContext,
    Map<String, dynamic>? capstoneHistory,
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    bool clearActiveSemester = false,
    bool clearEventName = false,
    bool clearYearLevel = false,
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
      workspace: workspace ?? this.workspace,
      yearLevel: clearYearLevel ? null : yearLevel ?? this.yearLevel,
      section: section ?? this.section,
      eventName: clearEventName ? null : eventName ?? this.eventName,
      pitEvents: pitEvents ?? this.pitEvents,
      rosterContext: rosterContext ?? this.rosterContext,
      capstoneHistory: capstoneHistory ?? this.capstoneHistory,
      historyIntake: historyIntake ?? this.historyIntake,
      historyPhase: historyPhase ?? this.historyPhase,
      historyStage: historyStage ?? this.historyStage,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class StudentTeamsNotifier extends Notifier<StudentTeamsState> {
  static String get baseUrl => ApiConfig.teamsUrl;
  int _previewRequestRevision = 0;
  int _fetchVersion = 0;
  String _listScope = 'active';

  @override
  StudentTeamsState build() {
    ref.onDispose(() => _fetchVersion++);
    return const StudentTeamsState();
  }

  Future<void> fetchTeams({
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {
    final version = ++_fetchVersion;
    final contextChanged =
        (scope != null && scope != _listScope) ||
        (historyIntake != null && historyIntake != state.historyIntake) ||
        (historyPhase != null && historyPhase != state.historyPhase) ||
        (historyStage != null && historyStage != state.historyStage);
    _listScope = scope ?? _listScope;
    final nextWorkspace = workspace ?? state.workspace;
    if (nextWorkspace != state.workspace) {
      state = StudentTeamsState(workspace: nextWorkspace);
    }
    String? resolvedLevel = level;
    if (resolvedLevel == null && state.level.isEmpty) {
      final user = ref.read(authProvider).user;
      final isAdmin =
          user != null &&
          (user['role']?.toString() == 'admin' || user['is_superuser'] == true);
      if (isAdmin) {
        resolvedLevel = 'Capstone';
      }
    }
    final nextSearch = search ?? state.search;
    final nextLevel = resolvedLevel ?? state.level;
    final nextStatus = status ?? state.status;
    final nextYearLevel = clearYearLevel
        ? null
        : (yearLevel ?? state.yearLevel);
    final nextSection = section ?? state.section;
    final nextEventName = clearEventName
        ? null
        : (eventName ?? state.eventName);

    state = state.copyWith(
      isLoading: contextChanged || state.teams.isEmpty,
      teams: contextChanged ? const [] : null,
      isSaving: false,
      search: nextSearch,
      level: nextLevel,
      status: nextStatus,
      yearLevel: nextYearLevel,
      clearYearLevel: clearYearLevel,
      section: nextSection,
      eventName: nextEventName,
      clearEventName: clearEventName,
      clearError: true,
      clearMessage: true,
      historyIntake: historyIntake,
      historyPhase: historyPhase,
      historyStage: historyStage,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextWorkspace.isNotEmpty) 'workspace': nextWorkspace,
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextLevel.isNotEmpty) 'level': nextLevel,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          'scope': _listScope,
          if (_listScope == 'history' && nextLevel == 'Capstone') ...{
            if (state.historyIntake.isNotEmpty)
              'intake_id': state.historyIntake,
            if (state.historyPhase.isNotEmpty) 'phase': state.historyPhase,
            if (state.historyStage.isNotEmpty) 'stage_key': state.historyStage,
          },
          if (nextYearLevel != null && nextYearLevel.isNotEmpty)
            'year_level': nextYearLevel,
          if (nextSection != null && nextSection.isNotEmpty)
            'section': nextSection,
          if (nextEventName != null && nextEventName.isNotEmpty)
            'event_name': nextEventName,
          if (nextEventName == null || nextEventName.isEmpty)
            'roster_view': 'current',
        },
      );
      final response = await _client.get(uri);
      if (!ref.mounted || version != _fetchVersion) return;

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
      if (!ref.mounted || version != _fetchVersion) return;
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

  Future<bool> updateTeam(int teamId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$teamId/').replace(
          queryParameters: {
            if (state.workspace.isNotEmpty) 'workspace': state.workspace,
          },
        ),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchTeams(successMessage: 'Team updated.');
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

  /// Load section choices without changing the directory's search or filters.
  Future<List<Map<String, dynamic>>> fetchSectionTeams({
    required String level,
    String scope = 'active',
    String? yearLevel,
    String? section,
  }) async {
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        if (state.workspace.isNotEmpty) 'workspace': state.workspace,
        if (level.isNotEmpty) 'level': level,
        'scope': scope,
        if (yearLevel?.isNotEmpty == true) 'year_level': yearLevel!,
        if (section?.isNotEmpty == true) 'section': section!,
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(_errorFromResponse(response));
    }
    final payload = Map<String, dynamic>.from(jsonDecode(response.body));
    return (payload['teams'] as List? ?? [])
        .whereType<Map>()
        .map((team) => Map<String, dynamic>.from(team))
        .toList();
  }

  Future<Map<String, dynamic>> fetchSectionDetails(int teamId) async {
    final response = await _client.get(Uri.parse('$baseUrl/$teamId/section/'));
    if (response.statusCode != 200) {
      throw Exception(_errorFromResponse(response));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  Future<bool> updateSectionDetails(
    int teamId,
    Map<String, dynamic> payload, {
    String? scope,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$teamId/section/'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        final details = Map<String, dynamic>.from(jsonDecode(response.body));
        final nextSection = state.section == payload['expected_section']
            ? details['section']?.toString()
            : state.section;
        await fetchTeams(
          section: nextSection,
          scope: scope,
          successMessage: 'Section details updated.',
        );
        _markDependentDataChanged();
        ref.read(dataRefreshProvider.notifier).markChanged(const [
          DataArea.teams,
          DataArea.academicRecords,
          DataArea.users,
          DataArea.repository,
        ]);
        return true;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
    return false;
  }

  Future<bool> deleteTeam(int teamId, {bool force = false}) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final urlStr = force
          ? '$baseUrl/$teamId/?force=true'
          : '$baseUrl/$teamId/';
      final response = await _client.delete(
        Uri.parse(urlStr).replace(
          queryParameters: {
            if (force) 'force': 'true',
            if (state.workspace.isNotEmpty) 'workspace': state.workspace,
          },
        ),
      );

      if (response.statusCode == 200) {
        await fetchTeams(successMessage: 'Team deleted.');
        _markDependentDataChanged();
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
    List<String>? csvColumns,
    String? section,
    String? systemName,
    String? projectManager,
  }) async {
    final requestRevision = ++_previewRequestRevision;
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
          if (state.eventName != null &&
              !state.level.toUpperCase().contains('CAPSTONE'))
            'event_name': state.eventName,
          'adviser_filter': adviserFilter,
          if (csvColumns != null) 'csv_columns': csvColumns,
          if (section != null) 'section': section,
          if (systemName != null) 'system_name': systemName,
          if (projectManager != null) 'project_manager': projectManager,
        }),
      );

      if (!ref.mounted || requestRevision != _previewRequestRevision) {
        return null;
      }
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      state = state.copyWith(error: _errorFromResponse(response));
      return null;
    } catch (e) {
      if (!ref.mounted || requestRevision != _previewRequestRevision) {
        return null;
      }
      state = state.copyWith(error: 'Connection error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> bulkImport(
    List<Map<String, dynamic>> rows, {
    String adviserFilter = 'all',
    List<String>? csvColumns,
    String? section,
    String? systemName,
    String? projectManager,
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
          if (state.eventName != null &&
              !state.level.toUpperCase().contains('CAPSTONE'))
            'event_name': state.eventName,
          'adviser_filter': adviserFilter,
          if (csvColumns != null) 'csv_columns': csvColumns,
          if (section != null) 'section': section,
          if (systemName != null) 'system_name': systemName,
          if (projectManager != null) 'project_manager': projectManager,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        await fetchTeams(
          successMessage: '$created teams imported. $errors row errors.',
        );
        _markDependentDataChanged();
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

  void _markDependentDataChanged() {
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.dashboard,
      DataArea.grades,
      DataArea.defenseBoard,
      DataArea.scheduler,
      DataArea.analytics,
      DataArea.audit,
    ]);
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  Future<void> refreshAfterGeneration(int count) async {
    _markDependentDataChanged();
    await fetchTeams(
      successMessage:
          '$count teams created. Leaders can complete team setup in their portal.',
    );
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
      capstoneMode: payload['capstone_mode']?.toString() ?? state.capstoneMode,
      canCreateCapstoneTeams: payload['can_create_capstone_teams'] == true,
      capstoneModeMessage: payload['capstone_mode_message']?.toString(),
      operatingMode: payload['operating_mode']?.toString() ?? 'active',
      operatingMessage: payload['operating_message']?.toString(),
      pitEvents: _readMapList(payload['pit_events']),
      rosterContext: _readMapList(payload['roster_context']),
      capstoneHistory: payload['capstone_history'] is Map
          ? Map<String, dynamic>.from(payload['capstone_history'])
          : const {},
      historyIntake: payload['capstone_history'] is Map
          ? payload['capstone_history']['selected_intake_id']?.toString() ?? ''
          : state.historyIntake,
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
      String messages(dynamic value) {
        if (value is List) {
          return value
              .map(messages)
              .where((text) => text.isNotEmpty)
              .join('\n');
        }
        if (value is Map) {
          return value.entries
              .where((entry) => entry.key != 'code')
              .map((entry) => messages(entry.value))
              .where((text) => text.isNotEmpty)
              .join('\n');
        }
        return value?.toString() ?? '';
      }

      if (data is Map) {
        final rows = data['errors'];
        if (rows is List) {
          final errors = <String>[];
          for (final row in rows.whereType<Map>()) {
            final detail = messages(row['errors']);
            if (detail.isEmpty) continue;
            final label = [
              if (row['sheet_row'] != null || row['row'] != null)
                'Row ${row['sheet_row'] ?? row['row']}',
              if ('${row['team_name'] ?? ''}'.isNotEmpty) '${row['team_name']}',
            ].join(' · ');
            errors.add(label.isEmpty ? detail : '$label: $detail');
          }
          if (errors.isNotEmpty) return errors.join('\n');
        }
        if (data['detail'] != null) {
          return messages(data['detail']);
        }
        if (data.isNotEmpty) {
          final detail = messages(data);
          if (detail.isNotEmpty) return detail;
        }
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }

    return 'Request failed. Status: ${response.statusCode}';
  }
}
