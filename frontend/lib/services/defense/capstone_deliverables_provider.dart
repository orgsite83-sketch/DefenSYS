import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/data_refresh_provider.dart';

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
  final String scope;
  final String workspace;
  final String? yearLevel;
  final String? section;
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
    this.selectedStage = '',
    this.search = '',
    this.status = '',
    this.scope = 'capstone',
    this.workspace = '',
    this.yearLevel,
    this.section,
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
    String? scope,
    String? workspace,
    String? yearLevel,
    String? section,
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
      scope: scope ?? this.scope,
      workspace: workspace ?? this.workspace,
      yearLevel: yearLevel ?? this.yearLevel,
      section: section ?? this.section,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  Map<String, dynamic>? get currentTeamSelectedStage {
    final team = teams.firstOrNull;
    if (team == null) return null;
    final stage = team['selected_stage'];
    if (stage is Map) {
      return Map<String, dynamic>.from(stage);
    }
    return null;
  }

  bool get hasPendingPreDeliverables =>
      StudentTaskBadgeHelper.hasPendingPreDeliverables(
        currentTeamSelectedStage,
      );

  bool get hasPendingPostDeliverables =>
      StudentTaskBadgeHelper.hasPendingPostDeliverables(
        currentTeamSelectedStage,
      );

  bool get hasPendingDeliverables =>
      hasPendingPreDeliverables || hasPendingPostDeliverables;
}

class StudentTaskBadgeHelper {
  static bool isTeamLeader(Map<String, dynamic>? data) {
    if (data == null) return false;
    final student = data['student'] as Map? ?? {};
    if (student['is_leader'] == true || student['isLeader'] == true) {
      return true;
    }
    final id = student['id'];
    if (id != null && '${data['team']?['leader_id']}' == '$id') return true;
    return (data['members'] as List? ?? []).whereType<Map>().any(
      (m) =>
          id != null &&
          '${m['id']}' == '$id' &&
          (m['isLeader'] == true || m['is_leader'] == true),
    );
  }

  static bool canEditConceptTitles(Map workflow) {
    if (workflow['can_edit_titles'] == false ||
        workflow['can_edit'] == false ||
        workflow['assigned'] == true ||
        workflow['module_names_confirmed'] == true) {
      return false;
    }
    return !const {
      'scheduled',
      'approved',
      'approved_with_revisions',
      'failed',
      'project_rejected',
      'for_redefense',
    }.contains(workflow['status']);
  }

  static bool hasPendingTeamTasks(
    Map<String, dynamic>? data, {
    Map<String, dynamic>? setup,
  }) {
    final teams = (setup?['teams'] as List? ?? []).whereType<Map>();
    final events = (setup?['event_teams'] as List? ?? []).whereType<Map>();
    final sectionTasks = (setup?['section_tasks'] as List? ?? [])
        .whereType<Map>();
    if (teams.any((t) => t['needs_name'] == true) ||
        events.any(
          (t) => t['needs_name'] == true || t['needs_details'] == true,
        ) ||
        sectionTasks.any(
          (t) =>
              t['role'] == 'project_manager' &&
              const {
                'papers_missing',
                'corrections_requested',
                'shared_revisions_pending',
                'final_paper_pending',
              }.contains(t['status']),
        )) {
      return true;
    }
    if (data == null || data['team'] is! Map) return false;
    final team = data['team'] as Map;
    if (!isTeamLeader(data)) return false;
    if (team['setup_pending'] == true || team['needs_name'] == true) {
      return true;
    }
    final options = (data['stage_options'] as List? ?? []);
    final rawLabel =
        '${team['currentStage'] ?? team['readyForStage'] ?? team['ready_for_stage'] ?? data['current_stage'] ?? ''}';
    final label =
        options.isEmpty ||
            options.any(
              (s) => '$s'.trim().toLowerCase() == rawLabel.trim().toLowerCase(),
            )
        ? rawLabel
        : '${options.first}';
    for (final stage in (data['stages'] as List? ?? []).whereType<Map>()) {
      if (label.isNotEmpty &&
          '${stage['stage_label']}'.trim().toLowerCase() !=
              label.trim().toLowerCase()) {
        continue;
      }
      if (stage['team_id'] != null && stage['team_id'] != team['id']) continue;
      final workflow = stage['concept_workflow'];
      if (workflow is! Map ||
          workflow['enabled'] != true ||
          !canEditConceptTitles(workflow)) {
        continue;
      }
      if ((workflow['concepts'] as List? ?? []).whereType<Map>().any(
        (c) =>
            c['faculty_confirmed'] != true &&
            '${c['title'] ?? ''}'.trim().isEmpty,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a deliverable item is pending required action (missing or needs revision).
  static bool isDeliverablePending(Map<String, dynamic> item) {
    if (item['is_waived'] == true) return false;
    // Defense-timed files can be supplied after endorsement. Until a date is
    // assigned, they are preparation work rather than an overdue task.
    if (item['requirement_timing'] == 'defense' &&
        item['materials_status'] == 'awaiting_schedule') {
      return false;
    }
    final uploaded = item['uploaded'] == true;
    final submission =
        item['submission'] as Map<String, dynamic>? ??
        (item['submission'] is Map
            ? Map<String, dynamic>.from(item['submission'] as Map)
            : null);
    final status = submission?['status']?.toString();
    final isRejected = status == 'rejected' || status == 'Needs Revision';
    if (item['type'] == 'pre' &&
        status == 'accepted' &&
        submission?['file_replacement_unlocked'] == true) {
      return true;
    }
    if (item['required'] != true) return false;
    if (item['requirement_timing'] == 'defense' &&
        item['materials_submitted'] is bool) {
      return item['materials_submitted'] != true;
    }

    if (!uploaded || submission == null || submission.isEmpty || isRejected) {
      return true;
    }
    return false;
  }

  /// Checks if there are pending required pre-defense deliverables.
  static bool hasPendingPreDeliverables(Map<String, dynamic>? stage) {
    if (stage == null) return false;
    final deliverables = stage['deliverables'] as List?;
    if (deliverables == null || deliverables.isEmpty) return false;

    return deliverables.any((d) {
      if (d is! Map) return false;
      final map = Map<String, dynamic>.from(d);
      if (map['type']?.toString() != 'pre') return false;
      return isDeliverablePending(map);
    });
  }

  /// Checks if there are pending required post-defense deliverables (only when unlocked).
  static bool hasPendingPostDeliverables(Map<String, dynamic>? stage) {
    return pendingPostDeliverablesCount(stage) > 0;
  }

  /// Counts pending required post-defense deliverables for a stage.
  static int pendingPostDeliverablesCount(Map<String, dynamic>? stage) {
    if (stage == null) return 0;
    final isUnlocked =
        stage['vault_unlocked'] == true ||
        stage['archive_unlocked'] == true ||
        stage['post_unlocked'] == true;
    if (!isUnlocked) return 0;

    final deliverables = stage['deliverables'] as List?;
    if (deliverables == null || deliverables.isEmpty) return 0;

    return deliverables.where((d) {
      if (d is! Map) return false;
      final map = Map<String, dynamic>.from(d);
      final itemType = map['type']?.toString();
      if (itemType != 'post' && itemType != 'vault') return false;
      return isDeliverablePending(map);
    }).length;
  }

  /// Returns the first stage from stagesList that has pending required post deliverables.
  static Map<String, dynamic>? firstStageWithPendingPostDeliverables(
    List<Map<String, dynamic>> stagesList,
  ) {
    for (final stage in stagesList) {
      if (hasPendingPostDeliverables(stage)) {
        return stage;
      }
    }
    return null;
  }

  /// Checks for required self-evaluations and teammate evaluations.
  static bool hasPendingPeerEval(Map<String, dynamic>? studentData) {
    if (studentData == null) return false;
    final peerEvalAllowed =
        studentData['peerEvalEnabled'] == true ||
        studentData['peer_eval_enabled'] == true;
    if (!peerEvalAllowed) return false;

    final members = (studentData['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .toList();
    if (members.isEmpty) return false;

    var mySubmissions = (studentData['myPeerSubmissions'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (mySubmissions.isEmpty) {
      final stages =
          (studentData['stages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final s in stages) {
        final stageSubs =
            (s['my_peer_submissions'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
        if (stageSubs.isNotEmpty) {
          mySubmissions = stageSubs;
          break;
        }
      }
    }

    final evaluatedKeys = <String>{};
    for (final sub in mySubmissions) {
      final id =
          sub['evaluateeId']?.toString() ?? sub['evaluatee_id']?.toString();
      if (id != null && id.isNotEmpty) {
        evaluatedKeys.add(id);
      }
      final name =
          (sub['evaluateeName']?.toString() ??
                  sub['evaluatee_name']?.toString() ??
                  '')
              .trim()
              .toLowerCase();
      if (name.isNotEmpty) {
        evaluatedKeys.add(name);
      }
    }

    return members.any((m) {
      final mId = m['id']?.toString() ?? '';
      final mName = (m['name']?.toString() ?? '').trim().toLowerCase();
      final isEvaluated = mId.isNotEmpty
          ? evaluatedKeys.contains(mId)
          : mName.isNotEmpty && evaluatedKeys.contains(mName);
      return !isEvaluated;
    });
  }

  /// Aggregates whether the student has any pending event action items.
  static bool hasPendingEvents({
    Map<String, dynamic>? selectedStage,
    Map<String, dynamic>? studentData,
  }) {
    final hasDeliverables =
        hasPendingPreDeliverables(selectedStage) ||
        hasPendingPostDeliverables(selectedStage);
    final hasPeer = hasPendingPeerEval(studentData);
    return hasDeliverables || hasPeer;
  }
}

class CapstoneDeliverablesNotifier extends Notifier<CapstoneDeliverablesState> {
  static String get baseUrl => ApiConfig.capstoneDeliverablesUrl;
  int _requestVersion = 0;
  bool _actionInFlight = false;

  Map<String, String> get _viewParameters => {
    if (state.search.trim().isNotEmpty) 'search': state.search.trim(),
    if (state.selectedStage.isNotEmpty) 'stage_label': state.selectedStage,
    if (state.status.isNotEmpty) 'status': state.status,
    'scope': state.scope,
    if (state.workspace.isNotEmpty) 'workspace': state.workspace,
    if (state.yearLevel?.isNotEmpty == true) 'year_level': state.yearLevel!,
    if (state.section?.isNotEmpty == true) 'section': state.section!,
  };

  @override
  CapstoneDeliverablesState build() {
    ref.onDispose(() => _requestVersion++);
    return const CapstoneDeliverablesState();
  }

  Future<void> fetchInitialData() => fetchDeliverables();

  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {
    final requestVersion = ++_requestVersion;
    final nextScope = scope ?? state.scope;
    final nextWorkspace = workspace ?? state.workspace;
    final workspaceChanged =
        nextWorkspace != state.workspace || nextScope != state.scope;
    final nextYearLevel =
        yearLevel ?? (workspaceChanged ? '' : state.yearLevel);
    final nextSection = section ?? (workspaceChanged ? '' : state.section);
    final contextChanged =
        nextWorkspace != state.workspace ||
        nextScope != state.scope ||
        nextYearLevel != state.yearLevel ||
        nextSection != state.section;
    final nextSearch = search ?? (contextChanged ? '' : state.search);
    final nextStage =
        selectedStage ?? (contextChanged ? '' : state.selectedStage);
    final nextStatus = status ?? (contextChanged ? '' : state.status);
    if (contextChanged) {
      state = CapstoneDeliverablesState(
        scope: nextScope,
        workspace: nextWorkspace,
        yearLevel: nextYearLevel,
        section: nextSection,
      );
    }

    state = state.copyWith(
      isLoading: state.teams.isEmpty,
      isSaving: _actionInFlight,
      search: nextSearch,
      selectedStage: nextStage,
      status: nextStatus,
      scope: nextScope,
      workspace: nextWorkspace,
      yearLevel: nextYearLevel,
      section: nextSection,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextStage.isNotEmpty) 'stage_label': nextStage,
          if (nextStatus.isNotEmpty) 'status': nextStatus,
          if (nextScope.isNotEmpty) 'scope': nextScope,
          if (nextWorkspace.isNotEmpty) 'workspace': nextWorkspace,
          if (nextYearLevel != null && nextYearLevel.isNotEmpty)
            'year_level': nextYearLevel,
          if (nextSection != null && nextSection.isNotEmpty)
            'section': nextSection,
        },
      );
      final response = await _client.get(uri);
      if (!ref.mounted || requestVersion != _requestVersion) return;

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isSaving: _actionInFlight,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      if (requestVersion != _requestVersion) return;
      state = state.copyWith(
        isLoading: false,
        isSaving: _actionInFlight,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> conceptAction(
    int teamId,
    String stageLabel,
    String action, {
    List<Map<String, dynamic>>? concepts,
    String? reason,
    String? reviewToken,
  }) => _postAction('concepts', {
    'team_id': teamId,
    'stage_label': stageLabel,
    'action': action,
    if (concepts != null) 'concepts': concepts,
    if (reason != null) 'reason': reason,
    if (reviewToken != null) 'review_token': reviewToken,
  }, successMessage: 'Concept workflow updated.');

  Future<bool> titleAction(
    int teamId,
    String stageLabel,
    String action, {
    required String conceptKey,
    required String reviewToken,
    int? roundId,
    String? title,
    String? reason,
  }) => _postAction('concepts', {
    'team_id': teamId,
    'stage_label': stageLabel,
    'action': action,
    'concept_key': conceptKey,
    'review_token': reviewToken,
    if (roundId != null) 'round_id': roundId,
    if (title != null) 'title': title,
    if (reason != null) 'reason': reason,
  }, successMessage: 'Title review updated.');

  Future<bool> reviewConceptFile({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String status,
    required int fileId,
    required String reviewToken,
    String feedback = '',
    String revisionScope = 'paper',
  }) => _postAction('review', {
    'team_id': teamId,
    'stage_label': stageLabel,
    'deliverable_id': deliverableId,
    'status': status,
    'file_id': fileId,
    'feedback': feedback,
    'revision_scope': revisionScope,
    'title_review_token': reviewToken,
  }, successMessage: 'File review updated.');

  Future<bool> confirmConceptTitle(
    int teamId,
    String stageLabel, {
    required String conceptKey,
    required int roundId,
    required String reviewToken,
    String? title,
  }) => _postAction('concepts', {
    'team_id': teamId,
    'stage_label': stageLabel,
    'action': 'confirm_title',
    'concept_key': conceptKey,
    'round_id': roundId,
    'review_token': reviewToken,
    if (title != null) 'title': title,
  }, successMessage: 'Module name confirmed.');

  Future<bool> uploadDocument({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String slotKey,
    required String filename,
    required Uint8List bytes,
    int? fileId,
  }) async {
    if (_actionInFlight) return false;
    _actionInFlight = true;
    final version = ++_requestVersion;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload/').replace(
          queryParameters: {..._viewParameters, 'response_mode': 'team'},
        ),
      );
      request.fields.addAll({
        'team_id': '$teamId',
        'stage_label': stageLabel,
        'deliverable_id': deliverableId,
        'slot_key': slotKey,
        'file_name': filename,
        'file_size': '${bytes.length} B',
        if (fileId != null) 'file_id': '$fileId',
      });
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
      final response = await http.Response.fromStream(
        await _client.sendAuthenticated(request, retryOn401: false),
      );
      if (response.statusCode != 200) {
        state = state.copyWith(error: _errorFromResponse(response));
        return false;
      }
      final payload = Map<String, dynamic>.from(jsonDecode(response.body));
      if (version != _requestVersion ||
          !_applyTeamPayload(payload, successMessage: 'Document uploaded.')) {
        await fetchDeliverables(successMessage: 'Document uploaded.');
      }
      _markDependentsChanged();
      return true;
    } catch (error) {
      state = state.copyWith(error: 'Could not upload the document: $error');
      return false;
    } finally {
      _actionInFlight = false;
      state = state.copyWith(isSaving: false);
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

  Future<bool> reviewAndEndorseTeam(
    int teamId,
    String stageLabel,
    String reviewToken,
  ) async {
    return _postAction(
      'review-endorse',
      {
        'team_id': teamId,
        'stage_label': stageLabel,
        'review_token': reviewToken,
      },
      successMessage: 'Scheduling files approved and team endorsed.',
    );
  }

  Future<bool> unendorseTeam(int teamId, String stageLabel) async {
    return _postAction('unendorse', {
      'team_id': teamId,
      'stage_label': stageLabel,
    }, successMessage: 'Team endorsement cancelled.');
  }

  Future<bool> reviewDeliverable({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String status,
    String? feedback,
    bool clearDefenseRevisions = false,
    int? fileId,
  }) async {
    return _postAction(
      'review',
      {
        'team_id': teamId,
        'stage_label': stageLabel,
        'deliverable_id': deliverableId,
        'status': status,
        if (fileId != null) 'file_id': fileId,
        if (feedback != null) 'feedback': feedback,
        if (clearDefenseRevisions) 'clear_defense_revisions': true,
      },
      successMessage: clearDefenseRevisions
          ? 'Deliverable approved & defense revisions cleared.'
          : 'Deliverable review status updated.',
    );
  }

  Future<bool> unlockDeliverables({
    int? teamId,
    required String stageLabel,
    String unlockType = 'all',
    String scope = 'team',
    String? programScope,
    String? yearLevel,
    bool? targetState,
    String reason = '',
    String? deliverableId,
  }) async {
    final Map<String, dynamic> payload = {
      'stage_label': stageLabel,
      'unlock_type': unlockType,
      'scope': scope,
      'reason': reason,
    };
    if (teamId != null) payload['team_id'] = teamId;
    if (programScope != null) payload['program_scope'] = programScope;
    if (yearLevel != null) payload['year_level'] = yearLevel;
    if (targetState != null) payload['target_state'] = targetState;
    if (deliverableId != null) payload['deliverable_id'] = deliverableId;

    return _postAction(
      'unlock',
      payload,
      successMessage: 'Deliverable submission unlock status updated.',
    );
  }

  Future<Map<String, dynamic>?> fetchStageAccess({
    String scope = 'global',
    String programScope = 'capstone',
    int? teamId,
    String? yearLevel,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/stage-access/').replace(
        queryParameters: {
          'scope': scope,
          'program_scope': programScope,
          if (teamId != null) 'team_id': '$teamId',
          if (yearLevel != null && yearLevel.isNotEmpty)
            'year_level': yearLevel,
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      state = state.copyWith(error: _errorFromResponse(response));
    } catch (e) {
      state = state.copyWith(error: 'Could not load stage access: $e');
    }
    return null;
  }

  Future<bool> _postAction(
    String action,
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    if (_actionInFlight) return false;
    _actionInFlight = true;
    final requestVersion = ++_requestVersion;
    final queryParameters = _viewParameters;
    final refreshTeam = const {
      'review',
      'endorse',
      'review-endorse',
      'concepts',
      'unendorse',
    }.contains(action);
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/$action/').replace(
          queryParameters: {
            ...queryParameters,
            if (refreshTeam) 'response_mode': 'team',
          },
        ),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final result = Map<String, dynamic>.from(jsonDecode(response.body));
        if (requestVersion != _requestVersion) {
          // A stage/filter changed during the write. Load its current snapshot
          // instead of merging a row from the old view.
          await fetchDeliverables(successMessage: successMessage);
        } else if (result['response_mode'] == 'team') {
          if (!_applyTeamPayload(result, successMessage: successMessage)) {
            await fetchDeliverables(successMessage: successMessage);
          }
        } else if (result['teams'] is List) {
          _applyPayload(result, successMessage: successMessage);
        } else {
          await fetchDeliverables(successMessage: successMessage);
        }
        _markDependentsChanged();
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
    } finally {
      _actionInFlight = false;
      state = state.copyWith(isSaving: false);
    }
  }

  void _markDependentsChanged() {
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.dashboard,
      DataArea.teams,
      DataArea.grades,
      DataArea.scheduler,
      DataArea.defenseBoard,
      DataArea.repository,
      DataArea.adviserGrades,
      DataArea.documenter,
    ]);
  }

  bool _applyTeamPayload(
    Map<String, dynamic> payload, {
    required String successMessage,
  }) {
    if (payload['team'] is! Map || payload['scope'] != state.scope) {
      return false;
    }
    final updated = Map<String, dynamic>.from(payload['team']);
    final teams = [...state.teams];
    final index = teams.indexWhere((team) => team['id'] == updated['id']);
    if (payload['matches_filters'] == false) {
      if (index >= 0) teams.removeAt(index);
    } else if (index >= 0) {
      teams[index] = updated;
    } else {
      // No loaded list means a complete fetch is needed to include other teams.
      return false;
    }
    if (teams.any((team) => team['counts'] is! Map)) return false;
    final contributions = teams.map((team) => team['counts'] as Map).toList();
    state = state.copyWith(
      teams: teams,
      counts: {
        for (final key in const [
          'teams',
          'ready',
          'missing_requirements',
          'pending_review',
          'submitted_files',
          'archive_files',
        ])
          key: contributions.fold<int>(
            0,
            (sum, row) => sum + (row[key] as num).toInt(),
          ),
        'deliverables_configured': contributions.any(
          (row) => row['deliverables_configured'] == true,
        ),
      },
      isLoading: false,
      isSaving: _actionInFlight,
      message: successMessage,
      clearError: true,
    );
    return true;
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: _actionInFlight,
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
      scope: payload['scope']?.toString() ?? state.scope,
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
