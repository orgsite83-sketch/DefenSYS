"""Pure display details for teams with and without a defense appointment."""


def stage_status_details(team, labels, progress):
    from repository.deliverables.services import team_stage_status

    # Current grades retain the attempt counter when the next attempt starts.
    # Never borrow a counter from another project version or academic period.
    attempts = {grade.stage_label: grade.attempt_count for grade in team.grade_records.all()
                if grade.semester_id == team.semester_id
                and grade.project_version == team.project_version}
    preparing = {'', 'pending', 'ready', 'awaiting_files', 'needs_review',
                 'changes_requested', 'awaiting_endorsement', 'ready_to_schedule_redefense'}
    statuses = {'missing': 'awaiting_files', 'needs_revision': 'changes_requested',
                'pending_review': 'needs_review', 'complete': 'awaiting_endorsement',
                'endorsed': 'endorsed', 'not_configured': 'not_configured'}
    result = {}
    for label in labels:
        detail = {'attempt_count': attempts.get(label, 1)}
        if progress.get(label, '') in preparing:
            detail['requirements_status'] = statuses.get(team_stage_status(team, label), 'unknown')
        result[label] = detail
    return result
