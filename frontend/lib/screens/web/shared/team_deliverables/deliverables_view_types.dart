import 'package:defensys/models/team_workflow_status.dart';

enum DeliverablesViewMode {
  dossier,
  matrix,
}

enum TeamTriageFilter {
  all,
  needsReview,
  awaitingEndorsement,
  readyForDefense,
  overdue,
  replacementConcepts,
  adviserReview,
  readyRedefense,
  redefenseScheduled,
  failed,
}

class DeliverablesTriageHelper {
  /// Dashboard summaries follow the current stage, independent of a historical
  /// stage selected in the deliverables workspace.
  static Map<String, dynamic>? resolveCurrentStage(Map<String, dynamic> team) {
    final current = team['current_stage']?.toString();
    for (final stage in (team['stages'] as List? ?? []).whereType<Map>()) {
      if (current != null && stage['stage_label']?.toString() == current) {
        return Map<String, dynamic>.from(stage);
      }
    }
    return resolveActiveStage(team);
  }

  static Map<String, dynamic>? resolveActiveStage(Map<String, dynamic> team) {
    final stages = (team['stages'] as List?)
            ?.whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList() ??
        [];
    final currentStageLabel = team['current_stage']?.toString();
    final selectedStageMap = team['selected_stage'] is Map
        ? Map<String, dynamic>.from(team['selected_stage'] as Map)
        : null;

    Map<String, dynamic>? activeStage = selectedStageMap;
    if (activeStage == null && currentStageLabel != null && currentStageLabel.isNotEmpty) {
      activeStage = stages.firstWhere(
        (s) => s['stage_label']?.toString() == currentStageLabel,
        orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
      );
    }
    if ((activeStage == null || activeStage.isEmpty) && stages.isNotEmpty) {
      activeStage = stages.first;
    }
    return activeStage != null && activeStage.isNotEmpty ? activeStage : null;
  }

  static List<Map> items(Map<String, dynamic> stage) => TeamWorkflowStatus.items(stage);

  static bool isPending(Map item) {
    return TeamWorkflowStatus.isPendingReview(item);
  }

  static int pendingReviewCount(Map<String, dynamic> team) {
    final stage = resolveActiveStage(team);
    return stage == null ? 0 : TeamWorkflowStatus.pendingReviewCount(stage);
  }

  static bool hasPendingReview(Map<String, dynamic> team) => pendingReviewCount(team) > 0;

  // Stable partition: preserve API ordering within each group and never mutate
  // provider state. Selection is tracked separately by team ID.
  static List<Map<String, dynamic>> reviewFirst(Iterable<Map<String, dynamic>> teams) {
    final pending = <Map<String, dynamic>>[];
    final other = <Map<String, dynamic>>[];
    for (final team in teams) {
      (hasPendingReview(team) ? pending : other).add(team);
    }
    return [...pending, ...other];
  }

  static bool isReadyForDefense(Map<String, dynamic> team) {
    final activeStage = resolveActiveStage(team);
    if (activeStage == null) return false;
    if (activeStage['has_active_schedule'] == true ||
        activeStage['has_done_schedule'] == true) {
      return false;
    }

    return !hasPendingReview(team) &&
        TeamWorkflowStatus.fromStage(activeStage).code == 'ready_to_schedule';
  }

  static bool isAwaitingEndorsement(Map<String, dynamic> team) {
    final stage = resolveActiveStage(team);
    return stage != null && TeamWorkflowStatus.fromStage(stage).code == 'awaiting_endorsement';
  }

  static bool isOverdueOrMissing(Map<String, dynamic> team) {
    final activeStage = resolveActiveStage(team);
    if (activeStage == null) return false;

    final materials = activeStage['materials_readiness'];
    if (materials is Map) {
      final required = int.tryParse('${materials['required_total'] ?? 0}') ?? 0;
      final submitted = int.tryParse('${materials['submitted_total'] ?? 0}') ?? 0;
      if (required > submitted) return true;
    }

    final statusDetail = activeStage['stage_status_detail']?.toString() ?? activeStage['status']?.toString();
    if (statusDetail == 'missing_requirements' || statusDetail == 'missing' || activeStage['required_complete'] == false) {
      final pre = (activeStage['pre'] as List?)?.whereType<Map>().toList() ?? [];
      final hasMissing = pre.any((d) => d['required'] == true && d['uploaded'] != true && d['is_waived'] != true);
      if (hasMissing || statusDetail == 'missing' || statusDetail == 'missing_requirements') return true;
    }
    return false;
  }

  static bool matchesFilter(Map<String, dynamic> team, TeamTriageFilter filter) {
    switch (filter) {
      case TeamTriageFilter.replacementConcepts:
        return (resolveActiveStage(team)?['concept_workflow'] as Map? ?? {})['status'] == 'replacement_concepts_needed';
      case TeamTriageFilter.adviserReview:
        return ['concept_review_pending', 'concept_endorsement_pending'].contains((resolveActiveStage(team)?['concept_workflow'] as Map? ?? {})['status']);
      case TeamTriageFilter.readyRedefense:
        return (resolveActiveStage(team)?['concept_workflow'] as Map? ?? {})['status'] == 'ready_to_schedule_redefense';
      case TeamTriageFilter.redefenseScheduled:
        final workflow = resolveActiveStage(team)?['concept_workflow'] as Map? ?? {};
        return workflow['status'] == 'scheduled' && (workflow['round'] as int? ?? 1) > 1;
      case TeamTriageFilter.failed:
        return ['failed', 'project_rejected'].contains(TeamWorkflowStatus.fromStage(resolveActiveStage(team) ?? {}).code);
      case TeamTriageFilter.all:
        return true;
      case TeamTriageFilter.needsReview:
        return hasPendingReview(team);
      case TeamTriageFilter.awaitingEndorsement:
        return isAwaitingEndorsement(team);
      case TeamTriageFilter.readyForDefense:
        return isReadyForDefense(team);
      case TeamTriageFilter.overdue:
        return isOverdueOrMissing(team);
    }
  }

  static Map<TeamTriageFilter, int> computeCounts(List<Map<String, dynamic>> teams) {
    int needsReview = 0;
    int awaitingEndorsement = 0;
    int ready = 0;
    int overdue = 0;

    for (final team in teams) {
      if (hasPendingReview(team)) needsReview++;
      if (isAwaitingEndorsement(team)) awaitingEndorsement++;
      if (isReadyForDefense(team)) ready++;
      if (isOverdueOrMissing(team)) overdue++;
    }

    return {
      for (final filter in TeamTriageFilter.values) filter: teams.where((team) => matchesFilter(team, filter)).length,
      TeamTriageFilter.all: teams.length,
      TeamTriageFilter.needsReview: needsReview,
      TeamTriageFilter.awaitingEndorsement: awaitingEndorsement,
      TeamTriageFilter.readyForDefense: ready,
      TeamTriageFilter.overdue: overdue,
    };
  }
}
