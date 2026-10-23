"""Shared presentation of semester grade scores and recorded defense outcomes."""

from collections import Counter
from decimal import Decimal

from grading.constants import PASS_GRADE_THRESHOLD


GRADE_OUTCOME_NOTE = (
    "PIT pass/fail marks indicate event scores only and do not restrict participation or decide semester results. "
    "Capstone outcome follows the recorded defense verdict. Configured hearings use the panel qualifying score; "
    "academic totals do not approve a defense. For unconfigured legacy numeric results, the grade "
    f"threshold is {PASS_GRADE_THRESHOLD:.0f}%. "
    "The average is for reference only. "
    "A defense approval does not change the numeric grade."
)


def grade_outcome_label(grade):
    """Identify the outcome's basis without replacing the grading workflow rule."""
    if grade.verdict == 'approved_with_revisions':
        return (
            'Approved (revisions cleared)'
            if grade.revisions_cleared_at else 'Revisions pending'
        )
    if grade.verdict:
        return grade.get_verdict_display()
    if grade.uses_defense_verdict and grade.schedule_id and grade.schedule.assessment_policy.get('version') == 1:
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
    scores = {
        name: getattr(student_grade, f'{name}_score', None)
        if student_grade is not None else None
        for name in ('panel', 'adviser', 'peer')
    }
    for name in scores:
        if scores[name] is None:
            scores[name] = getattr(grade, f'{name}_score')
    required = ['panel', 'peer']
    if grade.is_capstone and grade.adviser_weight > 0:
        required.append('adviser')
    final = student_grade.final_grade if student_grade is not None else grade.final_grade
    if any(scores[name] is None for name in required):
        final = None
    scores['final'] = final
    scores['status'] = (
        'Pending grading' if final is None
        else 'Grade passed' if final >= PASS_GRADE_THRESHOLD else 'Grade failed'
    )
    for name in ('panel', 'adviser', 'peer'):
        value = scores[name]
        scores[f'{name}_weighted'] = (
            (value * Decimal(getattr(grade, f'{name}_weight')) / Decimal('100')).quantize(Decimal('0.01'))
            if value is not None else None
        )
    return scores
