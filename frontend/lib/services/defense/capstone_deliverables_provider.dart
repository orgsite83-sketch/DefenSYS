import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

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
      StudentTaskBadgeHelper.hasPendingPreDeliverables(currentTeamSelectedStage);

  bool get hasPendingPostDeliverables =>
      StudentTaskBadgeHelper.hasPendingPostDeliverables(currentTeamSelectedStage);

  bool get hasPendingDeliverables =>
      hasPendingPreDeliverables || hasPendingPostDeliverables;
}

class StudentTaskBadgeHelper {
  /// Checks if a deliverable item is pending required action (missing or needs revision).
  static bool isDeliverablePending(Map<String, dynamic> item) {
    if (item['required'] != true) return false;
    final uploaded = item['uploaded'] == true;
    final submission = item['submission'] as Map<String, dynamic>? ??
        (item['submission'] is Map ? Map<String, dynamic>.from(item['submission'] as Map) : null);
    final status = submission?['status']?.toString();
    final isRejected = status == 'rejected' || status == 'Needs Revision';

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
    if (stage == null) return false;
    final isUnlocked = stage['vault_unlocked'] == true || stage['archive_unlocked'] == true;
    if (!isUnlocked) return false;

    final deliverables = stage['deliverables'] as List?;
    if (deliverables == null || deliverables.isEmpty) return false;

    return deliverables.any((d) {
      if (d is! Map) return false;
      final map = Map<String, dynamic>.from(d);
      final itemType = map['type']?.toString();
      if (itemType != 'post' && itemType != 'vault') return false;
      return isDeliverablePending(map);
    });
  }

  /// Checks if peer evaluations are enabled and there are pending evaluations for teammates.
  static bool hasPendingPeerEval(Map<String, dynamic>? studentData) {
    if (studentData == null) return false;
    final peerEvalAllowed = studentData['peerEvalEnabled'] == true ||
        studentData['peer_eval_enabled'] == true;
    if (!peerEvalAllowed) return false;

    final studentId = studentData['student']?['id']?.toString();
    final members = (studentData['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((m) => m['id']?.toString() != studentId)
        .toList();
    if (members.isEmpty) return false;

    final mySubmissions = (studentData['myPeerSubmissions'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final evaluatedKeys = <String>{};
    for (final sub in mySubmissions) {
      final id = sub['evaluateeId']?.toString() ?? sub['evaluatee_id']?.toString();
      if (id != null && id.isNotEmpty) {
        evaluatedKeys.add(id);
      } else {
        final name = sub['evaluateeName']?.toString() ?? sub['evaluatee_name']?.toString();
        if (name != null && name.isNotEmpty) {
          evaluatedKeys.add(name);
        }
      }
    }

    return members.any((m) {
      final mId = m['id']?.toString() ?? '';
      final mName = m['name']?.toString() ?? '';
      return !evaluatedKeys.contains(mId) && !evaluatedKeys.contains(mName);
    });
  }

  /// Aggregates whether the student has any pending event action items.
  static bool hasPendingEvents({
    Map<String, dynamic>? selectedStage,
    Map<String, dynamic>? studentData,
  }) {
    final hasDeliverables = hasPendingPreDeliverables(selectedStage) ||
        hasPendingPostDeliverables(selectedStage);
    final hasPeer = hasPendingPeerEval(studentData);
    return hasDeliverables || hasPeer;
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
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextStage = selectedStage ?? state.selectedStage;
    final nextStatus = status ?? state.status;
    final nextScope = scope ?? state.scope;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextSection = section ?? state.section;

    state = state.copyWith(
      isLoading: state.teams.isEmpty,
      isSaving: false,
      search: nextSearch,
      selectedStage: nextStage,
      status: nextStatus,
      scope: nextScope,
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
          if (nextYearLevel != null && nextYearLevel.isNotEmpty) 'year_level': nextYearLevel,
          if (nextSection != null && nextSection.isNotEmpty) 'section': nextSection,
        },
      );
      final response = await _client.get(uri);

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
  }) async {
    return _postAction('review', {
      'team_id': teamId,
      'stage_label': stageLabel,
      'deliverable_id': deliverableId,
      'status': status,
      if (feedback != null) 'feedback': feedback,
    }, successMessage: 'Deliverable review status updated.');
  }

  Future<bool> unlockDeliverables({
    int? teamId,
    required String stageLabel,
    String unlockType = 'all',
    String scope = 'team',
    String? programScope,
    String? yearLevel,
    bool? targetState,
  }) async {
    final Map<String, dynamic> payload = {
      'stage_label': stageLabel,
      'unlock_type': unlockType,
      'scope': scope,
    };
    if (teamId != null) payload['team_id'] = teamId;
    if (programScope != null) payload['program_scope'] = programScope;
    if (yearLevel != null) payload['year_level'] = yearLevel;
    if (targetState != null) payload['target_state'] = targetState;

    return _postAction('unlock', payload, successMessage: 'Deliverable submission unlock status updated.');
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
      final response = await _client.post(
        Uri.parse('$baseUrl/$action/'),

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

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

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
