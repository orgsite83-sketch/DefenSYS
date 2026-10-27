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
      'Review the required pre-defense files due before endorsement. Accept each submission or request corrections.',
    'changes_requested' =>
      'The team needs to submit the requested file corrections.',
    'awaiting_endorsement' =>
      'All team requirements for endorsement are complete. Endorse the team; shared scheduling checks are tracked separately when applicable.',
    'module_confirmation_pending' =>
      'Review and confirm the module names and their shared system connections before endorsing this team.',
    'ready_to_schedule' => 'The team is cleared for scheduling.',
    'scheduled' =>
      'A defense slot is assigned. Defense files remain due before the scheduled deadline.',
    'awaiting_evaluation' =>
      'Waiting for the assigned panelists to submit their evaluations.',
    'evaluating' => 'Panel evaluation is in progress.',
    'awaiting_verdict' =>
      'Panel evaluations are complete. Waiting for the defense decision.',
    'awaiting_concept_selection' =>
      'The panel chair needs to select one qualifying concept and record the decision.',
    'grading_incomplete' =>
      'Complete the remaining required grading components.',
    'awaiting_results' =>
      'Review the recorded assessment and remaining grading requirements.',
    'awaiting_completion' =>
      'Grading is ready. Waiting for authorized finalization.',
    'pending_post_defense' =>
      'The team needs to submit or correct the required post-defense files and complete any remaining documentation.',
    'archive_review_pending' =>
      'Review the submitted post-defense files for archiving. Accept each archive submission or request corrections.',
    'revisions_pending' =>
      'Complete and clear the revisions required by the defense decision.',
    'redefense_required' =>
      'Review re-defense requirements and authorization before scheduling another attempt.',
    'completed' =>
      'Required grading, documentation and file clearances are complete for this event or stage.',
    'replacement_concepts_needed' =>
      'Submit replacement concepts using the panel feedback.',
    'concept_review_pending' =>
      'Review the current concept papers and resolve any requested corrections.',
    'shared_clearance_pending' =>
      'Team endorsed. Waiting for the required shared documents to be accepted.',
    'shared_acknowledgment_pending' =>
      'Team endorsed. The assigned adviser/instructor needs to review and acknowledge the current shared proposals.',
    'ready_to_schedule_redefense' =>
      'The administrator can schedule the next defense attempt.',
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
      WorkflowStatusTone.active,
    ),
    'changes_requested' || 'needs_revision' => const TeamWorkflowStatus(
      'changes_requested',
      'Changes requested',
      WorkflowStatusTone.attention,
    ),
    'awaiting_endorsement' => const TeamWorkflowStatus(
      'awaiting_endorsement',
      'Awaiting endorsement',
      WorkflowStatusTone.active,
    ),
    'ready_to_schedule' ||
    'endorsed' ||
    'ready' ||
    'scheduling_eligible' => const TeamWorkflowStatus(
      'ready_to_schedule',
      'Ready to schedule',
      WorkflowStatusTone.success,
    ),
    'ready_to_schedule_redefense' => const TeamWorkflowStatus(
      'ready_to_schedule_redefense',
      'Ready to schedule re-defense',
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
      WorkflowStatusTone.neutral,
    ),
    'evaluating' || 'defense_ongoing' => const TeamWorkflowStatus(
      'evaluating',
      'Defense in progress',
      WorkflowStatusTone.active,
    ),
    'awaiting_verdict' => const TeamWorkflowStatus(
      'awaiting_verdict',
      'Awaiting verdict',
      WorkflowStatusTone.neutral,
    ),
    'awaiting_concept_selection' => const TeamWorkflowStatus(
      'awaiting_concept_selection',
      'Awaiting concept selection',
      WorkflowStatusTone.neutral,
    ),
    'grading_incomplete' => const TeamWorkflowStatus(
      'grading_incomplete',
      'Grading incomplete',
      WorkflowStatusTone.attention,
    ),
    'awaiting_results' || 'assessed' => const TeamWorkflowStatus(
      'awaiting_results',
      'Awaiting results',
      WorkflowStatusTone.neutral,
    ),
    'awaiting_completion' => const TeamWorkflowStatus(
      'awaiting_completion',
      'Awaiting completion',
      WorkflowStatusTone.neutral,
    ),
    'pending_post_defense' => const TeamWorkflowStatus(
      'pending_post_defense',
      'Awaiting post-defense',
      WorkflowStatusTone.neutral,
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

  static bool isPendingReview(Map item) => pendingFileReviewCount(item) > 0;

  static int pendingReviewCount(Map stage) => items(stage)
      .where(
        (item) => item['type'] != 'post' && item['deliverable_type'] != 'post',
      )
      .fold(0, (total, item) => total + pendingFileReviewCount(item));

  static int archivePendingReviewCount(Map stage) => items(stage)
      .where(
        (item) => item['type'] == 'post' || item['deliverable_type'] == 'post',
      )
      .fold(0, (total, item) => total + pendingFileReviewCount(item));

  static int pendingFileReviewCount(Map item) {
    final isPost = item['type'] == 'post' || item['deliverable_type'] == 'post';
    if ((!isPost && item['requirement_timing'] == 'defense') ||
        item['can_faculty_review'] == false ||
        item['is_waived'] == true ||
        item['source'] == 'defense_minutes') {
      return 0;
    }
    // `locked` controls student uploads, not whether a submitted file needs review.
    final submission = item['submission'];
    final files = submission is Map ? submission['files'] : null;
    if (files is List &&
        files.isEmpty &&
        submission is Map &&
        submission['file_history'] is List &&
        (submission['file_history'] as List).isNotEmpty &&
        submission['file_url'] == null) {
      return 0;
    }
    if (files is List && files.isNotEmpty) {
      return files
          .whereType<Map>()
          .where(
            (file) =>
                file['is_current'] != false && _pendingStatus(file['status']),
          )
          .length;
    }
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
    return uploaded && _pendingStatus(status) ? 1 : 0;
  }

  static bool _pendingStatus(dynamic status) =>
      status == null ||
      status.toString().isEmpty ||
      [
        'pending',
        'pending_review',
        'submitted',
      ].contains(status.toString().toLowerCase());

  /// Describes backend facts; never grants review, scheduling or upload access.
  static TeamWorkflowStatus fromStage(Map stage, {String scope = 'capstone'}) {
    final pending = pendingReviewCount(stage);
    if (pending > 0) {
      return TeamWorkflowStatus(
        'needs_review',
        '$pending needs review',
        WorkflowStatusTone.active,
      );
    }
    final concept = stage['concept_workflow'];
    if (concept is Map &&
        concept['enabled'] == true &&
        concept['can_edit'] == true) {
      final status = concept['status']?.toString();
      if (status == 'module_confirmation_pending') {
        if (items(stage).any(
          (item) =>
              item['required'] == true &&
              item['type'] != 'post' &&
              item['deliverable_type'] != 'post' &&
              item['requirement_timing'] != 'defense' &&
              item['is_waived'] != true &&
              item['uploaded'] == false,
        )) {
          return describe('awaiting_files');
        }
        return const TeamWorkflowStatus(
          'module_confirmation_pending',
          'Confirm module names',
          WorkflowStatusTone.active,
        );
      }
      if (status == 'shared_acknowledgment_pending') {
        return const TeamWorkflowStatus(
          'shared_acknowledgment_pending',
          'Team endorsed · Review shared systems',
          WorkflowStatusTone.attention,
        );
      }
      if (status == 'replacement_concepts_needed') {
        return const TeamWorkflowStatus(
          'replacement_concepts_needed',
          'Replacement concepts needed',
          WorkflowStatusTone.attention,
        );
      }
      if (status == 'concept_review_pending') {
        if (items(stage).any(
          (item) =>
              item['required'] == true &&
              item['type'] != 'post' &&
              item['requirement_timing'] != 'defense' &&
              item['is_waived'] != true &&
              (item['uploaded'] == false ||
                  (item['uploaded'] != true && item['submission'] == null)),
        )) {
          return describe('awaiting_files');
        } else {
          return TeamWorkflowStatus(
            'concept_review_pending',
            scope == 'pit'
                ? 'Instructor review pending'
                : 'Adviser review pending',
            WorkflowStatusTone.active,
          );
        }
      }
      if (status == 'shared_clearance_pending') {
        return const TeamWorkflowStatus(
          'shared_clearance_pending',
          'Team endorsed · Shared papers pending',
          WorkflowStatusTone.neutral,
        );
      }
      if (status == 'concept_endorsement_pending') {
        return describe('awaiting_endorsement');
      }
      if (status == 'ready_to_schedule_redefense') {
        return const TeamWorkflowStatus(
          'ready_to_schedule_redefense',
          'Ready to schedule re-defense',
          WorkflowStatusTone.success,
        );
      }
      if (status == 'ready_to_schedule') return describe('ready_to_schedule');
      if (status == 'concepts_needed') return describe('awaiting_files');
    }
    final assessment = stage['assessment_progress'];
    final recordedStatus = assessment is Map
        ? assessment['display_status']?.toString()
        : stage['stage_status_detail']?.toString() ??
              stage['status']?.toString();
    if (stage['repeat_preparation'] == true) {
      if (stage['endorsed'] == true) {
        return describe('ready_to_schedule_redefense');
      }
      if (items(stage).any(
        (item) =>
            item['type'] != 'post' &&
            item['submission'] is Map &&
            item['submission']['status'] == 'rejected',
      )) {
        return describe('changes_requested');
      }
      return describe(
        stage['required_complete'] == true
            ? 'awaiting_endorsement'
            : 'awaiting_files',
      );
    }
    final awaitingDecision =
        scope == 'capstone' &&
        assessment is Map &&
        const {
          'scheduled',
          'awaiting_evaluation',
          'evaluating',
          'awaiting_verdict',
          'awaiting_concept_selection',
          'for_redefense',
          'redefense_required',
          'failed',
          'project_rejected',
        }.contains(recordedStatus);
    final defenseDone =
        !awaitingDecision &&
        (assessment is Map && assessment['defense_approved'] is bool
            ? assessment['defense_approved'] == true
            : stage['is_defense_done'] == true ||
                  stage['has_done_schedule'] == true ||
                  const {
                    'awaiting_completion',
                    'completed',
                    'passed',
                    'pending_post_defense',
                  }.contains(recordedStatus));
    final archiveReviews = recordedStatus == 'completed'
        ? items(stage)
              .where(
                (item) =>
                    (item['type'] == 'post' ||
                        item['deliverable_type'] == 'post') &&
                    item['required'] != false,
              )
              .fold<int>(
                0,
                (total, item) => total + pendingFileReviewCount(item),
              )
        : archivePendingReviewCount(stage);
    if (defenseDone &&
        archiveReviews > 0 &&
        !const {
          'failed',
          'project_rejected',
          'for_redefense',
          'redefense_required',
          'revisions_pending',
          'cancelled',
          'archived',
        }.contains(recordedStatus)) {
      return TeamWorkflowStatus(
        'archive_review_pending',
        '$archiveReviews archive ${archiveReviews == 1 ? 'file needs' : 'files need'} review',
        WorkflowStatusTone.active,
      );
    }
    final missingPostFiles =
        (stage['shared_deliverables_summary'] is Map && stage['shared_deliverables_summary']['post_complete'] == false) ||
        stage['archive_complete'] == false ||
        items(stage).any(
          (item) =>
              (item['type'] == 'post' || item['deliverable_type'] == 'post') &&
              item['required'] == true &&
              item['is_waived'] != true &&
              item['source'] != 'defense_minutes' &&
              (item['uploaded'] == false ||
                  item['submission'] == null ||
                  (item['submission'] is Map &&
                      item['submission']['status'] != 'accepted')),
        );
    if (defenseDone &&
        missingPostFiles &&
        !const {
          'failed',
          'project_rejected',
          'for_redefense',
          'redefense_required',
          'revisions_pending',
          'cancelled',
          'archived',
        }.contains(recordedStatus)) {
      return describe('pending_post_defense');
    }
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
    // With file reviews cleared, preserve the recorded defense workflow state.
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
      'awaiting_concept_selection',
      'ready_to_schedule_redefense',
      'awaiting_files',
      'changes_requested',
      'needs_review',
      'grading_incomplete',
      'awaiting_completion',
      'assessed',
      'awaiting_results',
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
      final shared = stage['shared_deliverables_summary'];
      if (shared is Map && shared['pre_complete'] == false) {
        return const TeamWorkflowStatus('shared_clearance_pending', 'Shared documents pending', WorkflowStatusTone.attention);
      }
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
