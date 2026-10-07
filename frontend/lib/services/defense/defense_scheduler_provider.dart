import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/dashboard_provider.dart';
import 'defense_board_provider.dart';
import '../admin/user_management_provider.dart';

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
  final List<Map<String, dynamic>> documenters;
  final List<Map<String, dynamic>> faculty;
  final List<Map<String, dynamic>> panelistRequests;
  final List<Map<String, dynamic>> createdInvitations;
  final bool canApprovePanelists;
  final bool requiresPanelistApproval;
  final List<Map<String, dynamic>> generatedSlots;
  final List<String> statuses;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String schedulerMode;
  final String pitOperatingMode;
  final String? operatingMessage;
  final bool canSchedulePit;
  final bool canScheduleCapstone;
  final List<String> allowedScopes;
  final List<Map<String, dynamic>> pitEvents;
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
    this.documenters = const [],
    this.faculty = const [],
    this.panelistRequests = const [],
    this.createdInvitations = const [],
    this.canApprovePanelists = false,
    this.requiresPanelistApproval = false,
    this.generatedSlots = const [],
    this.statuses = const [],
    this.counts = const {},
    this.activeSemester,
    this.schedulerMode = '',
    this.pitOperatingMode = 'active',
    this.operatingMessage,
    this.canSchedulePit = false,
    this.canScheduleCapstone = false,
    this.allowedScopes = const [],
    this.pitEvents = const [],
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
    List<Map<String, dynamic>>? documenters,
    List<Map<String, dynamic>>? faculty,
    List<Map<String, dynamic>>? panelistRequests,
    List<Map<String, dynamic>>? createdInvitations,
    bool? canApprovePanelists,
    bool? requiresPanelistApproval,
    List<Map<String, dynamic>>? generatedSlots,
    List<String>? statuses,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? schedulerMode,
    String? pitOperatingMode,
    String? operatingMessage,
    bool? canSchedulePit,
    bool? canScheduleCapstone,
    List<String>? allowedScopes,
    List<Map<String, dynamic>>? pitEvents,
    String? search,
    String? scope,
    String? status,
    String? error,
    String? message,
    bool clearActiveSemester = false,
    bool clearOperatingMessage = false,
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
      documenters: documenters ?? this.documenters,
      faculty: faculty ?? this.faculty,
      panelistRequests: panelistRequests ?? this.panelistRequests,
      createdInvitations: createdInvitations ?? this.createdInvitations,
      canApprovePanelists: canApprovePanelists ?? this.canApprovePanelists,
      requiresPanelistApproval:
          requiresPanelistApproval ?? this.requiresPanelistApproval,
      generatedSlots: generatedSlots ?? this.generatedSlots,
      statuses: statuses ?? this.statuses,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      schedulerMode: schedulerMode ?? this.schedulerMode,
      pitOperatingMode: pitOperatingMode ?? this.pitOperatingMode,
      operatingMessage: clearOperatingMessage
          ? null
          : operatingMessage ?? this.operatingMessage,
      canSchedulePit: canSchedulePit ?? this.canSchedulePit,
      canScheduleCapstone: canScheduleCapstone ?? this.canScheduleCapstone,
      allowedScopes: allowedScopes ?? this.allowedScopes,
      pitEvents: pitEvents ?? this.pitEvents,
      search: search ?? this.search,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  List<Map<String, dynamic>> get selectablePanelists =>
      canApprovePanelists && faculty.isNotEmpty ? faculty : panelists;

  bool isEligiblePanelist(int id) =>
      panelists.any((p) => p['id'] == id) ||
      faculty.any((p) => p['id'] == id && p['is_panelist'] == true);

  int? get currentCapstoneStageId {
    final stages = defenseStages.where((s) => s['is_active'] != false).toList();
    if (stages.isEmpty) return null;

    // 1. Explicit flag if present (from backend serializer or override)
    for (final stage in stages) {
      if (stage['is_current'] == true || stage['is_current_stage'] == true) {
        final id = _parseId(stage['id']);
        if (id != null) return id;
      }
    }

    final incompleteStages =
        stages.where((s) => s['is_officially_complete'] != true).toList();
    if (incompleteStages.isEmpty) {
      return _parseId(stages.first['id']);
    }

    // 2. Count active/ready capstone teams per incomplete stage
    int maxCount = 0;
    int? bestStageId;

    for (final stage in incompleteStages) {
      final stageLabel = stage['label']?.toString().trim() ?? '';
      if (stageLabel.isEmpty) continue;

      int count = 0;
      for (final team in teams) {
        final level = team['level']?.toString().toLowerCase() ?? '';
        final isCapstone =
            level.contains('capstone') || team['is_capstone'] == true;
        if (!isCapstone) continue;

        final readyFor = team['ready_for_stage']?.toString().trim();
        final currentDefense = team['current_defense_stage']?.toString().trim();
        final currentStage = team['current_stage']?.toString().trim();
        final scheduledStages = team['scheduled_stages'] is List
            ? (team['scheduled_stages'] as List)
                .map((e) => e?.toString().trim())
                .toList()
            : const [];

        if (readyFor == stageLabel ||
            currentDefense == stageLabel ||
            currentStage == stageLabel ||
            scheduledStages.contains(stageLabel)) {
          count++;
        }
      }

      final endorsedCount = _parseId(stage['endorsed_teams_count']) ?? 0;
      if (count < endorsedCount) {
        count = endorsedCount;
      }

      final hasActiveSchedules = schedules.any((s) {
        if (_parseId(s['defense_stage_id']) != _parseId(stage['id'])) {
          return false;
        }
        final status = s['status']?.toString().toLowerCase();
        return status == 'scheduled' || status == 'in_progress';
      });
      if (hasActiveSchedules && count == 0) {
        count = 1;
      }

      if (count > maxCount) {
        maxCount = count;
        bestStageId = _parseId(stage['id']);
      } else if (count > 0 && count == maxCount) {
        // Later stage in sequence takes priority if tied with active teams
        bestStageId = _parseId(stage['id']);
      }
    }

    if (bestStageId != null && maxCount > 0) {
      return bestStageId;
    }

    // 3. Fallback: First incomplete stage in sequence
    return _parseId(incompleteStages.first['id']);
  }

  bool isCurrentCapstoneStage(dynamic stage) {
    final currentId = currentCapstoneStageId;
    if (currentId == null) return false;
    if (stage is Map) {
      return _parseId(stage['id']) == currentId;
    }
    if (stage is int) {
      return stage == currentId;
    }
    return false;
  }

  String formatStageLabel(Map<String, dynamic> stage) {
    final label = stage['label']?.toString() ?? '';
    if (isCurrentCapstoneStage(stage)) {
      return '$label (current stage)';
    }
    return label;
  }

  static int? _parseId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class DefenseSchedulerNotifier extends Notifier<DefenseSchedulerState> {
  static String get baseUrl => ApiConfig.defenseSchedulesUrl;

  @override
  DefenseSchedulerState build() {
    return const DefenseSchedulerState();
  }

  /// Import validation needs every active appointment, including those hidden
  /// by the board's search, scope or status filters. Do not change those filters.
  Future<List<Map<String, dynamic>>> fetchImportConflictSchedules() async {
    final response = await _client.get(
      Uri.parse(baseUrl).replace(queryParameters: {'status': 'scheduled'}),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorFromResponse(response));
    }
    final payload = Map<String, dynamic>.from(jsonDecode(response.body));
    return _readMapList(payload['schedules']);
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
          faculty: _readMapList(data['faculty']),
          panelistRequests: _readMapList(data['panelist_requests']),
          canApprovePanelists: data['can_approve_panelists'] == true,
          requiresPanelistApproval: data['requires_panelist_approval'] == true,
          pitEvents: _readMapList(data['pit_events']),
          activeSemester: data['active_semester'] is Map
              ? Map<String, dynamic>.from(data['active_semester'])
              : state.activeSemester,
          schedulerMode:
              data['scheduler_mode']?.toString() ?? state.schedulerMode,
          pitOperatingMode:
              data['pit_operating_mode']?.toString() ?? state.pitOperatingMode,
          operatingMessage: data['operating_message']?.toString(),
          clearOperatingMessage: data['operating_message'] == null,
          canSchedulePit: data['can_schedule_pit'] == true,
          canScheduleCapstone: data['can_schedule_capstone'] == true,
          allowedScopes: _readStringList(data['allowed_scopes']),
          message: '${data['slot_count'] ?? 0} teams assigned · ${data['unassigned_count'] ?? 0} remaining.',
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
        await _refreshDependentProviders();
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
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          createdInvitations: _readMapList(data['created_invitations']),
        );
        await _refreshDependentProviders();
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

  Future<Map<String, dynamic>> importSchedules(
    List<Map<String, dynamic>> payloads,
  ) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    var created = 0;
    final errors = <String>[];
    final importedIndices = <int>[];

    for (var index = 0; index < payloads.length; index++) {
      try {
        final response = await _client.post(
          Uri.parse('$baseUrl/'),
          body: jsonEncode(payloads[index]),
        );
        if (response.statusCode == 201) {
          created++;
          importedIndices.add(index);
        } else {
          errors.add('Row ${index + 1}: ${_errorFromResponse(response)}');
        }
      } catch (e) {
        errors.add('Row ${index + 1}: Connection error: $e');
      }
    }

    await fetchSchedules();
    await _refreshDependentProviders();

    if (errors.isNotEmpty && created == 0) {
      state = state.copyWith(error: errors.first);
    }

    return {
      'created': created,
      'errors': errors,
      'imported_indices': importedIndices,
    };
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

  Future<bool> savePitEventConfig(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/pit-event-config/'),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          message: 'PIT event configuration saved successfully.',
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

  Future<List<Map<String, dynamic>>> fetchPitEventConfigs({
    int? semesterId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/pit-event-config/').replace(
        queryParameters: {
          if (semesterId != null) 'semester_id': semesterId.toString(),
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return [];
      }
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final configs = data['configs'];
      if (configs is List) {
        return configs.map((c) => Map<String, dynamic>.from(c as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> deletePitEventConfig(int configId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(
        '$baseUrl/pit-event-config/',
      ).replace(queryParameters: {'config_id': configId.toString()});
      final response = await _client.delete(uri);

      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          message: 'PIT event configuration deleted successfully.',
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

  Future<bool> deleteSchedule(int scheduleId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(Uri.parse('$baseUrl/$scheduleId/'));

      if (response.statusCode == 200) {
        await fetchSchedules(successMessage: 'Schedule deleted.');
        await _refreshDependentProviders();
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

  Future<bool> patchSchedule(
    int scheduleId,
    Map<String, dynamic> payload,
  ) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$scheduleId/'),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchSchedules(successMessage: 'Schedule updated.');
        await _refreshDependentProviders();
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

  Future<void> _refreshDependentProviders() async {
    try {
      await ref
          .read(dashboardProvider('admin').notifier)
          .fetchDashboardData(silent: true);
    } catch (_) {}
    try {
      await ref.read(defenseBoardProvider.notifier).fetchBoard();
    } catch (_) {}
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  Future<bool> requestPanelistEligibility(int facultyId, String reason) async {
    return _panelistRequestMutation(
      '${ApiConfig.usersUrl}/panelist-requests/',
      {'faculty_id': facultyId, 'reason': reason},
      success:
          'Eligibility request submitted. Your schedule selections are retained.',
    );
  }

  /// Uses the canonical RBAC endpoint so role history and pending requests stay
  /// in sync. Only this duty is patched; other roles and credentials are retained.
  Future<bool> setPanelistEligibility(
    int facultyId, {
    required bool eligible,
  }) async {
    if (!state.canApprovePanelists) {
      state = state.copyWith(
        error: 'Only admins can change panelist eligibility.',
      );
      return false;
    }
    final ok = await _panelistRequestMutation(
      '${ApiConfig.usersUrl}/$facultyId/',
      {'is_panelist': eligible},
      patch: true,
      success: eligible
          ? 'Faculty member added to the eligible panelist pool.'
          : 'Panelist eligibility removed.',
    );
    if (ok) {
      await ref.read(userManagementProvider.notifier).fetchUsers();
    }
    return ok;
  }

  Future<bool> reviewPanelistEligibility(
    int requestId, {
    required bool approve,
    String note = '',
  }) async {
    final ok = await _panelistRequestMutation(
      '${ApiConfig.usersUrl}/panelist-requests/$requestId/',
      {'decision': approve ? 'approved' : 'declined', 'review_note': note},
      patch: true,
      success: approve
          ? 'Panelist eligibility approved for future defenses.'
          : 'Eligibility request declined.',
    );
    if (ok && approve) {
      await ref.read(userManagementProvider.notifier).fetchUsers();
    }
    return ok;
  }

  Future<bool> _panelistRequestMutation(
    String url,
    Map<String, dynamic> payload, {
    bool patch = false,
    required String success,
  }) async {
    try {
      final response = patch
          ? await _client.patch(Uri.parse(url), body: jsonEncode(payload))
          : await _client.post(Uri.parse(url), body: jsonEncode(payload));
      if (response.statusCode != 200 && response.statusCode != 201) {
        state = state.copyWith(error: _errorFromResponse(response));
        return false;
      }
      await fetchSchedules(successMessage: success);
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Connection error: $e');
      return false;
    }
  }

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
      documenters: _readMapList(payload['documenters']),
      faculty: _readMapList(payload['faculty']),
      panelistRequests: _readMapList(payload['panelist_requests']),
      createdInvitations: _readMapList(payload['created_invitations']),
      canApprovePanelists: payload['can_approve_panelists'] == true,
      requiresPanelistApproval: payload['requires_panelist_approval'] == true,
      pitEvents: _readMapList(payload['pit_events']),
      statuses: _readStringList(payload['statuses']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      schedulerMode:
          payload['scheduler_mode']?.toString() ?? state.schedulerMode,
      pitOperatingMode:
          payload['pit_operating_mode']?.toString() ?? state.pitOperatingMode,
      operatingMessage: payload['operating_message']?.toString(),
      clearOperatingMessage: payload['operating_message'] == null,
      canSchedulePit: payload['can_schedule_pit'] == true,
      canScheduleCapstone: payload['can_schedule_capstone'] == true,
      allowedScopes: _readStringList(payload['allowed_scopes']),
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
