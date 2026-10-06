/// Assessment progress is separate from schedule dates and the panel outcome.
String defenseProgressLabel(String status) => switch (status) {
  'scheduled' => 'Scheduled',
  'awaiting_evaluation' => 'Awaiting evaluation',
  'evaluating' || 'ongoing' => 'Evaluating',
  'awaiting_verdict' => 'Awaiting verdict',
  'revisions_pending' => 'Revisions pending',
  'redefense_required' || 'for_redefense' => 'Re-defense required',
  'grading_incomplete' => 'Grading incomplete',
  'awaiting_completion' => 'Awaiting completion',
  'failed' => 'Failed',
  'project_rejected' => 'Project rejected',
  'assessed' || 'done' => 'Attempt assessed',
  'completed' => 'Completed',
  'paused' => 'Interrupted',
  'postponed' => 'Postponed',
  'no_show' => 'No-show',
  'cancelled' => 'Cancelled',
  'archived' => 'Archived',
  _ => status.replaceAll('_', ' '),
};

String defenseVerdictLabel(String? verdict) => switch (verdict) {
  'approved' => 'Approved',
  'approved_with_revisions' => 'Approved with Revisions',
  'for_redefense' => 'For Re-defense',
  'failed' => 'Failed',
  'project_rejected' => 'Project Rejected',
  _ => 'Awaiting verdict',
};
