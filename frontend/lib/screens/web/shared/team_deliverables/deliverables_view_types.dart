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

  static bool hasPendingReview(Map<String, dynamic> team) {
    final activeStage = resolveActiveStage(team);
    if (activeStage == null) return false;

    final pre = (activeStage['pre'] as List?)?.whereType<Map>().toList() ?? [];
    final post = (activeStage['post'] as List?)?.whereType<Map>().toList() ?? [];
    final allDeliverables = (activeStage['deliverables'] as List?)?.whereType<Map>().toList() ??
        [...pre, ...post];

    for (final d in allDeliverables) {
      final isUploaded = d['uploaded'] == true ||
          d['status'] == 'submitted' ||
          d['status'] == 'pending' ||
          d['submission_status'] == 'submitted' ||
          d['submission_status'] == 'pending';
      if (isUploaded && d['is_waived'] != true) {
        final sub = d['submission'];
        if (sub is Map) {
          final status = sub['status']?.toString().toLowerCase();
          if (status == null ||
              status.isEmpty ||
              status == 'pending' ||
              status == 'pending_review' ||
              status == 'submitted') {
            return true;
          }
        } else {
          return true;
        }
      }
    }

    final isPresentationOnly = activeStage['is_presentation_only'] == true;
    final configured = activeStage['deliverables_configured'] == true || isPresentationOnly;
    final complete = activeStage['required_complete'] == true || isPresentationOnly;
    final endorsed = activeStage['endorsed'] == true;
    if (configured && complete && !endorsed) {
      return true;
    }

    return false;
  }

  static bool isReadyForDefense(Map<String, dynamic> team) {
    final activeStage = resolveActiveStage(team);
    if (activeStage == null) return false;

    final endorsed = activeStage['endorsed'] == true;
    final statusDetail = activeStage['stage_status_detail']?.toString() ?? activeStage['status']?.toString();
    final complete = activeStage['required_complete'] == true || activeStage['status'] == 'ready';

    return endorsed || statusDetail == 'endorsed' || statusDetail == 'ready' || complete;
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
