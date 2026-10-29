"""Shared presentation of semester grade scores and recorded defense outcomes."""

from collections import Counter

from grading.constants import PASS_GRADE_THRESHOLD


GRADE_OUTCOME_NOTE = (
    "PIT pass/fail marks indicate event scores only and do not restrict participation or decide semester results. "
    "Capstone outcome follows the panel assessment and official stage disposition. Configured hearings use the panel qualifying score; "
    "academic totals do not approve a defense. For unconfigured legacy numeric results, the grade "
    f"threshold is {PASS_GRADE_THRESHOLD:.0f}%. "
    "The average is for reference only. "
    "A defense approval does not change the numeric grade."
)


def grade_outcome_label(grade):
    """Identify the outcome's basis without replacing the grading workflow rule."""
    if grade.closed_as_failed:
        return 'Failed (stage closure)'
    if grade.verdict == 'approved_with_revisions':
        return (
            'Approved (revisions cleared)'
            if grade.revisions_cleared_at else 'Revisions pending'
        )
    if grade.verdict:
        return grade.get_verdict_display()
    if grade.uses_defense_verdict and grade.schedule_id and grade.schedule.assessment_policy.get('version') == 1:
        from grading.grades.outcome_rules import automatic_outcomes, outcome_payload
        if automatic_outcomes(grade.schedule):
            rule = outcome_payload(grade)
            return 'Awaiting concept selection' if rule['panel_complete'] and rule['outcome'] == 'approved' else 'Awaiting panel assessment'
        return 'Awaiting defense decision'
    if grade.final_grade is None:
        return 'Pending grades'
    return 'Grade passed' if grade.result == 'passed' else 'Grade failed'


def assessment_panel_submissions(grade, *, official=True):
    """Never mix another hearing, void scores, or alternative concepts into a grade."""
    rows = grade.panelist_submissions.filter(is_void=False)
    if grade.schedule_id:
        rows = rows.filter(schedule_id=grade.schedule_id)
        from grading.grades.outcome_rules import policy_for, selected_key
        if official and policy_for(grade.schedule).get('per_concept'):
            key = selected_key(grade.schedule)
            if key is None:
                return rows.none()
            rows = rows.filter(concept_key=key)
    return rows.select_related('panelist', 'student').prefetch_related('criterion_scores')


def summarize_grade_records(grade_records):
    """Count teams separately from stage/event records and include every outcome."""
    outcomes = Counter(grade.result or 'pending' for grade in grade_records)
    completed = [grade.final_grade for grade in grade_records if grade.final_grade is not None]
    return {
        'team_count': len({grade.team_id for grade in grade_records}),
        'record_count': len(grade_records),
        'outcomes': outcomes,
        'average': sum(completed) / len(completed) if completed else None,
    }


def outcome_breakdown(summary):
    counts = summary['outcomes']
    return '; '.join([
        f"Passed / approved: {counts['passed']}",
        f"Failed / rejected: {counts['failed']}",
        f"Revisions pending: {counts['revisions_pending']}",
        f"For re-defense: {counts['for_redefense']}",
        f"Pending grades: {counts['pending']}",
    ])


def assessment_scope_label(grade):
    return 'Capstone' if grade.scope == 'capstone' else 'PIT'


def student_assessment_scores(grade, student_grade=None):
    """Use the stored final grade; missing required ratings remain pending."""
    from grading.grades.masterlist import component_values
    components, final = component_values(grade, student_grade, individual=True)
    scores = {name: values['score'] for name, values in components.items()}
    scores['final'] = final
    scores['status'] = (
        'Pending grading' if final is None
        else 'Grade passed' if final >= PASS_GRADE_THRESHOLD else 'Grade failed'
    )
    for name in ('panel', 'adviser', 'peer'):
        scores[f'{name}_weighted'] = components[name]['weighted']
    return scores
