import 'package:defensys/models/team_workflow_status.dart';

import 'schedule_import_models.dart';

bool teamMatchesStatusEvent(
  Map<String, dynamic> team,
  Map<String, dynamic> event,
) {
  final year = event['year_level']?.toString() ?? '';
  if (year.isEmpty || team['year_level']?.toString() != year) return false;
  final details = team['stage_status_details'];
  return details is! Map || details.containsKey(event['event_name']);
}

enum TeamStatusGroup {
  all('All teams'),
  beforeScheduling('Before scheduling'),
  scheduled('Scheduled'),
  followUp('Follow-up'),
  completed('Completed');

  const TeamStatusGroup(this.label);
  final String label;
}

/// Display only: scheduling and review authorization stay in their services.
class TeamStatus {
  const TeamStatus(this.code, this.label, this.tone, this.nextStep);

  final String code;
  final String label;
  final WorkflowStatusTone tone;
  final String nextStep;

  TeamStatusGroup get group => switch (code) {
    'completed' => TeamStatusGroup.completed,
    'scheduled' ||
    'redefense_scheduled' ||
    're_demo_scheduled' => TeamStatusGroup.scheduled,
    'awaiting_evaluation' ||
    'evaluating' ||
    'awaiting_verdict' ||
    'awaiting_concept_selection' ||
    'grading_incomplete' ||
    'awaiting_completion' ||
    'pending_post_defense' ||
    'revisions_pending' ||
    'redefense_required' ||
    'ready_to_schedule_redefense' ||
    'ready_for_retake' ||
    're_demo_required' ||
    'failed' ||
    'project_rejected' ||
    'assessed' ||
    'paused' ||
    'postponed' ||
    'no_show' ||
    'cancelled' ||
    'archived' => TeamStatusGroup.followUp,
    _ => TeamStatusGroup.beforeScheduling,
  };

  static TeamStatus describe(String code, {String scope = 'capstone'}) {
    final reviewer = scope == 'pit' ? 'Instructor' : 'Adviser';
    final shared = TeamWorkflowStatus.describe(code);
    final label = switch (code) {
      'awaiting_files' => 'Awaiting requirements',
      'redefense_scheduled' => 'Re-defense scheduled',
      'ready_for_retake' => 'Ready to schedule retake',
      'shared_clearance_pending' => 'Shared papers pending',
      'shared_acknowledgment_pending' => 'Shared review pending',
      'shared_setup_pending' => 'Shared proposals needed',
      'module_confirmation_pending' => 'Confirm module names',
      'replacement_concepts_needed' => 'Replacement concepts needed',
      'concept_review_pending' => '$reviewer review pending',
      'scheduling_blocked' => 'Scheduling blocked',
      'assessed' => 'Attempt assessed',
      'unknown' => 'Status unavailable',
      _ => shared.label,
    };
    final next = switch (code) {
      'awaiting_files' => 'Team to submit the required files.',
      'needs_review' ||
      'concept_review_pending' => '$reviewer to review submissions.',
      'changes_requested' => 'Team to submit the requested corrections.',
      'awaiting_endorsement' => '$reviewer to endorse the team.',
      'ready_to_schedule' => 'Assign a defense slot.',
      'ready_to_schedule_redefense' => 'Assign a re-defense slot.',
      'ready_for_retake' => 'Assign the authorized retake slot.',
      'scheduled' || 'redefense_scheduled' => 'Attend the scheduled defense.',
      'awaiting_evaluation' ||
      'evaluating' => 'Panelists to complete evaluations.',
      'awaiting_verdict' => 'Panel chair to confirm the verdict.',
      'awaiting_concept_selection' =>
        'Panel chair to record the selected concept.',
      'grading_incomplete' => 'Complete the remaining grading components.',
      'awaiting_completion' => 'Complete authorized finalization.',
      'pending_post_defense' => 'Submit and clear post-defense requirements.',
      'revisions_pending' => 'Complete and clear the required revisions.',
      'redefense_required' => 'Clear re-defense requirements and endorsement.',
      're_demo_required' => 'Assign a re-demo slot.',
      're_demo_scheduled' => 'Demonstrate corrections to the assigned panel.',
      'completed' => 'No remaining work for this stage or event.',
      'replacement_concepts_needed' => 'Team to submit replacement concepts.',
      'shared_clearance_pending' => 'Complete and clear the shared papers.',
      'shared_acknowledgment_pending' =>
        '$reviewer to acknowledge the shared proposals.',
      'shared_setup_pending' => 'Project manager to open the shared proposals.',
      'module_confirmation_pending' => '$reviewer to confirm module names.',
      'not_configured' => 'Configure stage or event requirements.',
      'scheduling_blocked' => 'Review scheduling requirements and eligibility.',
      'failed' || 'project_rejected' =>
        'Review the recorded outcome and permitted next steps.',
      'paused' ||
      'postponed' ||
      'no_show' => 'Review the interruption and arrange the next step.',
      'cancelled' ||
      'archived' ||
      'assessed' => 'Review the retained defense record.',
      _ => 'Review the team requirements and recorded status.',
    };
    return TeamStatus(code, label, switch (code) {
      'redefense_scheduled' => WorkflowStatusTone.active,
      'ready_for_retake' => WorkflowStatusTone.success,
      'scheduling_blocked' ||
      'replacement_concepts_needed' ||
      'shared_clearance_pending' ||
      'shared_setup_pending' => WorkflowStatusTone.attention,
      'concept_review_pending' ||
      'module_confirmation_pending' ||
      'shared_acknowledgment_pending' => WorkflowStatusTone.active,
      _ => shared.tone,
    }, next);
  }

  static TeamStatus fromTeam(
    Map<String, dynamic> team,
    String stageLabel, {
    required String scope,
    Map<String, dynamic> event = const {},
  }) {
    TeamStatus status(String code) => describe(code, scope: scope);
    if (stageLabel.isEmpty) return status('not_configured');
    final detail =
        (team['stage_status_details'] as Map?)?[stageLabel] as Map? ?? {};
    final concept =
        (team['concept_workflows'] as Map?)?[stageLabel] as Map? ?? {};
    final raw = (team['stage_progress'] as Map?)?[stageLabel]?.toString() ?? '';
    const requirementCodes = {
      'awaiting_files',
      'needs_review',
      'changes_requested',
      'awaiting_endorsement',
      'ready_to_schedule_redefense',
    };
    final code =
        requirementCodes.contains(raw) ||
            {
              'pending_post_defense',
              'awaiting_concept_selection',
              'cancelled',
            }.contains(raw)
        ? raw
        : getTeamStageStatus(team, stageLabel);
    if (code == 'completed') return status(code);
    if (code == 'scheduled') {
      return status(
        (asInt(detail['attempt_count']) ?? 1) > 1 ||
                (asInt(concept['round']) ?? 1) > 1
            ? 'redefense_scheduled'
            : 'scheduled',
      );
    }
    if (code == 'failed' && isTeamStageReady(team, stageLabel)) {
      return status('ready_for_retake');
    }
    if (!{
      'pending',
      'ready',
      'redefense_required',
      ...requirementCodes,
    }.contains(code)) {
      return status(code == 'done' ? 'assessed' : code);
    }

    final conceptCode = concept['status']?.toString() ?? '';
    final repeat =
        code == 'redefense_required' ||
        code == 'ready_to_schedule_redefense' ||
        (team['stage_verdicts'] as Map?)?[stageLabel] == 'for_redefense' ||
        (team['redefense_stages'] as List? ?? []).contains(stageLabel) ||
        (asInt(concept['round']) ?? 1) > 1 ||
        conceptCode == 'ready_to_schedule_redefense';
    const conceptStates = {
      'replacement_concepts_needed',
      'concept_review_pending',
      'module_confirmation_pending',
      'shared_clearance_pending',
      'shared_acknowledgment_pending',
      'shared_setup_pending',
    };
    final titlePending =
        concept['title_workflow_version'] == 2 &&
        concept['can_edit'] == true &&
        {
          'draft',
          'parent_pending',
          'submitted',
          'changes_requested',
        }.contains(conceptCode);
    final conceptBlocked =
        conceptStates.contains(conceptCode) ||
        titlePending ||
        {
          'concepts_needed',
          'concept_endorsement_pending',
        }.contains(conceptCode);
    final ready = scope == 'pit'
        ? isPitTeamReadyToSchedule(team, stageLabel, event)
        : isTeamStageReady(team, stageLabel);
    if (ready && !conceptBlocked) {
      return status(
        repeat ? 'ready_to_schedule_redefense' : 'ready_to_schedule',
      );
    }

    final requirementsCode =
        detail['requirements_status']?.toString() ??
        (requirementCodes.contains(raw) ? raw : 'unknown');
    var preparation = status(
      requirementsCode == 'endorsed' ? 'scheduling_blocked' : requirementsCode,
    );
    final shared = sharedSchedulingReadiness(team, stageLabel);
    if (shared['complete'] == false) {
      final requirements = (shared['requirements'] as List? ?? [])
          .whereType<Map>();
      final sharedCode =
          requirements.any((row) => row['status'] == 'changes_requested')
          ? 'shared_changes_requested'
          : requirements.any((row) => row['status'] == 'awaiting_upload')
          ? 'shared_files_missing'
          : 'shared_review_pending';
      preparation = TeamStatus(
        sharedCode,
        sharedRequirementsStatus(shared),
        WorkflowStatusTone.attention,
        sharedRequirementsDetail(shared),
      );
    } else if (titlePending) {
      final label = concept['title_status_label']?.toString() ?? '';
      preparation = TeamStatus(
        'concept_$conceptCode',
        label.isEmpty ? 'Concept review pending' : label,
        conceptCode == 'changes_requested'
            ? WorkflowStatusTone.attention
            : WorkflowStatusTone.active,
        concept['next_step']?.toString() ??
            'Review the current concept titles.',
      );
    } else if (conceptStates.contains(conceptCode)) {
      preparation = status(conceptCode);
    } else if (conceptCode == 'concepts_needed') {
      preparation = status('awaiting_files');
    } else if (conceptCode == 'concept_endorsement_pending') {
      preparation = status('awaiting_endorsement');
    }
    if (repeat) {
      final result = status('redefense_required');
      return TeamStatus(
        result.code,
        result.label,
        result.tone,
        {'unknown', 'scheduling_blocked'}.contains(preparation.code)
            ? result.nextStep
            : preparation.nextStep,
      );
    }
    return preparation;
  }
}
