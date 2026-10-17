/// Presentation categories shared by PIT event and Capstone stage statuses.
enum WorkflowStatusTone { neutral, attention, destructive, active, success }

class TeamWorkflowStatus {
  final String code;
  final String label;
  final WorkflowStatusTone tone;

  const TeamWorkflowStatus(this.code, this.label, this.tone);

  String get nextStep => switch (code) {
    'not_configured' => 'Configure the requirements for this event or stage.',
    'awaiting_files' =>
      'The team needs to upload the required before-endorsement files.',
    'needs_review' =>
      'Review the submitted files, then accept or reject each submission.',
    'changes_requested' =>
      'The team needs to submit the requested file corrections.',
    'awaiting_endorsement' =>
      'All required before-endorsement files are accepted. Endorse the team for scheduling.',
    'ready_to_schedule' => 'The team is cleared for scheduling.',
    'scheduled' =>
      'A defense slot is assigned. Defense files remain due before the scheduled deadline.',
    'awaiting_evaluation' =>
      'Waiting for the assigned panelists to submit their evaluations.',
    'evaluating' => 'Panel evaluation is in progress.',
    'awaiting_verdict' =>
      'Panel evaluations are complete. Waiting for the defense decision.',
    'grading_incomplete' =>
      'Complete the remaining required grading components.',
    'awaiting_results' =>
      'Review the recorded assessment and remaining grading requirements.',
    'awaiting_completion' =>
      'Grading is ready. Waiting for authorized finalization.',
    'pending_post_defense' =>
      'Review the required post-defense files and remaining documentation.',
    'revisions_pending' =>
      'Complete and clear the revisions required by the defense decision.',
    'redefense_required' =>
      'Review re-defense requirements and authorization before scheduling another attempt.',
    'completed' =>
      'Required grading, documentation and file clearances are complete for this event or stage.',
    'replacement_concepts_needed' => 'Submit replacement concepts using the panel feedback.',
    'concept_review_pending' => 'Review the current concept papers and resolve any requested corrections.',
    'ready_to_schedule_redefense' => 'The administrator can schedule the next defense attempt.',
    'failed' || 'project_rejected' =>
      'Review the recorded outcome and any authorized next steps.',
    'paused' ||
    'postponed' ||
    'no_show' => 'Review the recorded schedule interruption and next steps.',
    'cancelled' || 'archived' => 'Review the retained event or stage record.',
    _ => 'Review the event or stage requirements and recorded status.',
  };

  static TeamWorkflowStatus describe(String code) => switch (code) {
    'not_configured' => const TeamWorkflowStatus(
      'not_configured',
      'Not configured',
      WorkflowStatusTone.neutral,
    ),
    'awaiting_files' || 'missing' => const TeamWorkflowStatus(
      'awaiting_files',
      'Awaiting files',
      WorkflowStatusTone.neutral,
    ),
    'needs_review' || 'pending_review' => const TeamWorkflowStatus(
      'needs_review',
      'Needs review',
      WorkflowStatusTone.attention,
    ),
    'changes_requested' || 'needs_revision' => const TeamWorkflowStatus(
      'changes_requested',
      'Changes requested',
      WorkflowStatusTone.attention,
    ),
    'awaiting_endorsement' => const TeamWorkflowStatus(
      'awaiting_endorsement',
      'Awaiting endorsement',
      WorkflowStatusTone.attention,
    ),
    'ready_to_schedule' ||
    'endorsed' ||
    'ready' ||
    'scheduling_eligible' => const TeamWorkflowStatus(
      'ready_to_schedule',
      'Ready to schedule',
      WorkflowStatusTone.success,
    ),
    'scheduled' || 'defense_scheduled' => const TeamWorkflowStatus(
      'scheduled',
      'Scheduled',
      WorkflowStatusTone.active,
    ),
    'awaiting_evaluation' => const TeamWorkflowStatus(
      'awaiting_evaluation',
      'Awaiting evaluation',
      WorkflowStatusTone.attention,
    ),
    'evaluating' || 'defense_ongoing' => const TeamWorkflowStatus(
      'evaluating',
      'Defense in progress',
      WorkflowStatusTone.active,
    ),
    'awaiting_verdict' => const TeamWorkflowStatus(
      'awaiting_verdict',
      'Awaiting verdict',
      WorkflowStatusTone.attention,
    ),
    'grading_incomplete' => const TeamWorkflowStatus(
      'grading_incomplete',
      'Grading incomplete',
      WorkflowStatusTone.attention,
    ),
    'awaiting_results' || 'assessed' => const TeamWorkflowStatus(
      'awaiting_results',
      'Awaiting results',
      WorkflowStatusTone.attention,
    ),
    'awaiting_completion' => const TeamWorkflowStatus(
      'awaiting_completion',
      'Awaiting completion',
      WorkflowStatusTone.attention,
    ),
    'pending_post_defense' => const TeamWorkflowStatus(
      'pending_post_defense',
      'Post-defense requirements',
      WorkflowStatusTone.attention,
    ),
    'revisions_pending' => const TeamWorkflowStatus(
      'revisions_pending',
      'Revisions pending',
      WorkflowStatusTone.attention,
    ),
    'redefense_required' || 'for_redefense' => const TeamWorkflowStatus(
      'redefense_required',
      'Re-defense required',
      WorkflowStatusTone.attention,
    ),
    'completed' => const TeamWorkflowStatus(
      'completed',
      'Completed',
      WorkflowStatusTone.success,
    ),
    'passed' => const TeamWorkflowStatus(
      'passed',
      'Passed',
      WorkflowStatusTone.success,
    ),
    'failed' => const TeamWorkflowStatus(
      'failed',
      'Failed',
      WorkflowStatusTone.destructive,
    ),
    'project_rejected' => const TeamWorkflowStatus(
      'project_rejected',
      'Project rejected',
      WorkflowStatusTone.destructive,
    ),
    'paused' => const TeamWorkflowStatus(
      'paused',
      'Interrupted',
      WorkflowStatusTone.attention,
    ),
    'postponed' => const TeamWorkflowStatus(
      'postponed',
      'Postponed',
      WorkflowStatusTone.attention,
    ),
    'no_show' => const TeamWorkflowStatus(
      'no_show',
      'No-show',
      WorkflowStatusTone.attention,
    ),
    'cancelled' => const TeamWorkflowStatus(
      'cancelled',
      'Cancelled',
      WorkflowStatusTone.neutral,
    ),
    'archived' => const TeamWorkflowStatus(
      'archived',
      'Archived',
      WorkflowStatusTone.neutral,
    ),
    _ => const TeamWorkflowStatus(
      'on_hold',
      'On hold',
      WorkflowStatusTone.neutral,
    ),
  };

  static List<Map> items(Map stage) =>
      (stage['deliverables'] as List?)?.whereType<Map>().toList() ??
      [
        ...(stage['pre'] as List? ?? []).whereType<Map>(),
        ...(stage['post'] as List? ?? []).whereType<Map>(),
      ];

  static bool isPendingReview(Map item) {
    if (item['requirement_timing'] == 'defense' ||
        item['is_waived'] == true ||
        item['locked'] == true) {
      return false;
    }
    final submission = item['submission'];
    final status =
        (submission is Map
                ? submission['status']
                : item['submission_status'] ?? item['status'])
            ?.toString()
            .toLowerCase();
    final uploaded =
        item['uploaded'] == true ||
        submission is Map ||
        ['pending', 'pending_review', 'submitted'].contains(status);
    return uploaded &&
        (status == null ||
            status.isEmpty ||
            ['pending', 'pending_review', 'submitted'].contains(status));
  }

  /// Describes backend facts; never grants review, scheduling or upload access.
  static TeamWorkflowStatus fromStage(Map stage, {String scope = 'capstone'}) {
    final concept = stage['concept_workflow'];
    if (concept is Map && concept['enabled'] == true && concept['can_edit'] == true) {
      final status = concept['status']?.toString();
      if (status == 'replacement_concepts_needed') return const TeamWorkflowStatus('replacement_concepts_needed', 'Replacement concepts needed', WorkflowStatusTone.attention);
      if (status == 'concept_review_pending') return TeamWorkflowStatus('concept_review_pending', scope == 'pit' ? 'Instructor review pending' : 'Adviser review pending', WorkflowStatusTone.attention);
      if (status == 'concept_endorsement_pending') return describe('awaiting_endorsement');
      if (status == 'ready_to_schedule_redefense') return const TeamWorkflowStatus('ready_to_schedule_redefense', 'Ready to schedule re-defense', WorkflowStatusTone.active);
      if (status == 'ready_to_schedule') return describe('ready_to_schedule');
      if (status == 'concepts_needed') return describe('awaiting_files');
    }
    final assessment = stage['assessment_progress'];
    if (assessment is Map && assessment['display_status'] is String) {
      final status = assessment['display_status'] as String;
      final completed =
          assessment['is_completed'] == true || status == 'completed';
      if (completed) {
        return describe(
          stage['archive_complete'] == false ||
                  stage['documentation_complete'] == false
              ? 'pending_post_defense'
              : 'completed',
        );
      }
      return describe(status);
    }

    final detail =
        stage['stage_status_detail']?.toString() ?? stage['status']?.toString();
    // Preserve later workflow states even when another file still needs review.
    if (const {
      'failed',
      'project_rejected',
      'for_redefense',
      'redefense_required',
      'revisions_pending',
      'pending_post_defense',
      'passed',
      'completed',
      'defense_scheduled',
      'scheduled',
      'defense_ongoing',
      'evaluating',
      'awaiting_evaluation',
      'awaiting_verdict',
      'grading_incomplete',
      'awaiting_completion',
      'assessed',
      'paused',
      'postponed',
      'no_show',
      'cancelled',
      'archived',
    }.contains(detail)) {
      return describe(detail!);
    }

    if (stage['has_active_schedule'] == true) return describe('scheduled');
    if (stage['has_done_schedule'] == true) return describe('awaiting_results');

    final configured =
        stage['deliverables_configured'] == true ||
        stage['is_presentation_only'] == true;
    if (stage['deliverables_configured'] == false && !configured ||
        stage.isEmpty) {
      return describe('not_configured');
    }
    if (stage['endorsed'] == true ||
        const {'endorsed', 'ready', 'scheduling_eligible'}.contains(detail) ||
        scope == 'pit' && stage['endorsement_required'] == false) {
      return describe('ready_to_schedule');
    }

    final scheduling = items(stage).where(
      (item) =>
          item['type'] != 'post' &&
          item['deliverable_type'] != 'post' &&
          item['requirement_timing'] != 'defense' &&
          item['is_waived'] != true,
    );
    if (scheduling.any(
      (item) =>
          item['submission'] is Map &&
          item['submission']['status'] == 'rejected',
    )) {
      return describe('changes_requested');
    }
    if (scheduling.any(isPendingReview) || detail == 'pending_review') {
      return describe('needs_review');
    }
    if (stage['required_complete'] == true) {
      final review = stage['endorsement_review'];
      if (review is Map && review['can_review_and_endorse'] == false) {
        return describe('on_hold');
      }
      return describe('awaiting_endorsement');
    }
    return describe('awaiting_files');
  }
}
