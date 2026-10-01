enum DeliverablesViewMode {
  dossier,
  matrix,
}

enum TeamTriageFilter {
  all,
  needsReview,
  readyForDefense,
  overdue,
}

class DeliverablesTriageHelper {
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

  static List<Map> items(Map<String, dynamic> stage) =>
      (stage['deliverables'] as List?)?.whereType<Map>().toList() ??
      [...(stage['pre'] as List? ?? []).whereType<Map>(),
       ...(stage['post'] as List? ?? []).whereType<Map>()];

  static bool isPending(Map item) {
    if (item['is_waived'] == true || item['locked'] == true) return false;
    final submission = item['submission'];
    final status = (submission is Map ? submission['status'] :
        item['submission_status'] ?? item['status'])?.toString().toLowerCase();
    final uploaded = item['uploaded'] == true || submission is Map ||
        ['pending', 'pending_review', 'submitted'].contains(status);
    return uploaded && (status == null || status.isEmpty ||
        ['pending', 'pending_review', 'submitted'].contains(status));
  }

  static int pendingReviewCount(Map<String, dynamic> team) {
    final stage = resolveActiveStage(team);
    return stage == null ? 0 : items(stage).where(isPending).length;
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

    final endorsed = activeStage['endorsed'] == true;
    final statusDetail = activeStage['stage_status_detail']?.toString() ?? activeStage['status']?.toString();
    return !hasPendingReview(team) &&
        (endorsed || statusDetail == 'endorsed' || statusDetail == 'ready');
  }

  static bool isOverdueOrMissing(Map<String, dynamic> team) {
    final activeStage = resolveActiveStage(team);
    if (activeStage == null) return false;

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
      case TeamTriageFilter.all:
        return true;
      case TeamTriageFilter.needsReview:
        return hasPendingReview(team);
      case TeamTriageFilter.readyForDefense:
        return isReadyForDefense(team);
      case TeamTriageFilter.overdue:
        return isOverdueOrMissing(team);
    }
  }

  static Map<TeamTriageFilter, int> computeCounts(List<Map<String, dynamic>> teams) {
    int needsReview = 0;
    int ready = 0;
    int overdue = 0;

    for (final team in teams) {
      if (hasPendingReview(team)) needsReview++;
      if (isReadyForDefense(team)) ready++;
      if (isOverdueOrMissing(team)) overdue++;
    }

    return {
      TeamTriageFilter.all: teams.length,
      TeamTriageFilter.needsReview: needsReview,
      TeamTriageFilter.readyForDefense: ready,
      TeamTriageFilter.overdue: overdue,
    };
  }
}
