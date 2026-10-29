"""Write-side resolution of captured automatic hearings, never a GET repair."""
from copy import deepcopy

from django.core.exceptions import ValidationError
from django.db import transaction

from .models import TeamGrade
from .outcome_rules import automatic_outcomes, hearing_concepts, outcome_payload


def recommendations_unavailable_reason(grade, actor):
    from .defense_workflow import is_chair
    from django.utils import timezone
    if not is_chair(grade, actor):
        return 'Only the assigned panel chair can save team recommendations.'
    if grade.status in TeamGrade.LOCKED_STATUSES:
        return 'This assessment is finalized.'
    if grade.schedule.status not in ('scheduled', 'done') or grade.schedule.operation_state != 'normal' or grade.schedule.scheduled_date > timezone.localdate():
        return 'Recommendations are unavailable for this hearing in its current state.'
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).first()
    if hearing and ConceptRound.objects.filter(team_id=grade.team_id, project_version=grade.project_version,
        defense_stage_id=grade.defense_stage_id, number=hearing.number + 1, schedule__isnull=False).exists():
        return 'The next hearing has started; earlier recommendations are read-only.'
    return ''


def _locked_grade(grade):
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    StudentTeam.objects.select_for_update().get(pk=grade.team_id)
    schedule_id = TeamGrade.objects.values_list('schedule_id', flat=True).get(pk=grade.pk)
    if schedule_id:
        DefenseSchedule.objects.select_for_update().get(pk=schedule_id)
    if schedule_id != grade.schedule_id:
        raise ValidationError('The defense attempt changed. Refresh before editing this assessment.')
    return TeamGrade.objects.select_for_update(of=('self',)).select_related(
        'team', 'schedule', 'semester', 'defense_stage').get(pk=grade.pk)


@transaction.atomic
def resolve_outcome(grade, *, actor=None, selected_key=None, review_token=None):
    if not automatic_outcomes(grade.schedule):
        return grade
    grade = _locked_grade(grade)
    from .defense_workflow import require_current, is_chair, _record_outcome
    require_current(grade)
    if grade.verdict or grade.status in TeamGrade.LOCKED_STATUSES:
        if selected_key is not None:
            raise ValidationError('This hearing outcome is already recorded. Refresh the assessment.')
        return grade
    rule = outcome_payload(grade)
    if not rule or not rule['panel_complete'] or rule['outcome'] == 'pending':
        if selected_key is not None:
            raise ValidationError((rule or {}).get('reason') or 'Wait for every required panel evaluation.')
        return grade
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).select_related('section_round').first()
    section = hearing.section_round if hearing and hearing.section_round_id else None
    candidates = [row['key'] for row in rule['assessments'] if row['qualifies']
        and (not section or row['key'] == section.selected_key)]
    if selected_key is not None:
        if not is_chair(grade, actor):
            raise PermissionError('Only the assigned panel chair can select the official concept.')
        if review_token != rule['review_token']:
            raise ValidationError('The assessment changed. Refresh before selecting a concept.')
        if len(candidates) < 2 or selected_key not in candidates:
            raise ValidationError('Select one of the qualifying concepts awaiting a chair choice.')
    elif len(candidates) > 1 and rule['per_concept']:
        return grade
    chosen = selected_key if selected_key is not None else candidates[0] if candidates else None
    verdict = 'approved' if rule['outcome'] == 'approved' else 'for_redefense'
    section_retry = bool(section and section.verdict == 'for_redefense')
    notes = section.remarks if section_retry else grade.verdict_remarks
    decisions = None
    if rule['per_concept']:
        decisions = []
        for concept in hearing_concepts(grade.schedule):
            requested = verdict == 'for_redefense' and (
                not section or section_retry or concept['key'] == section.selected_key)
            decisions.append({'key': concept['key'],
                'decision': 'approved' if concept['key'] == chosen and verdict == 'approved'
                    else 'revise' if requested else 'not_selected',
                'remarks': notes if requested else '',
                'next_action': ('replace' if section_retry else 'revise') if requested else 'omit'})
    result = _record_outcome(grade, actor=actor, verdict=verdict, remarks=notes,
        concept_decisions=decisions, replacement_concepts_required=section_retry, automatic=True)
    # Other callers can retain the object created before the last submission.
    grade.refresh_from_db()
    return result


@transaction.atomic
def save_recommendations(grade, *, actor, notes, review_token=None):
    if not automatic_outcomes(grade.schedule):
        raise ValidationError('This hearing uses the captured manual assessment workflow.')
    if not isinstance(notes, str) or len(notes) > 5000:
        raise ValidationError('Enter recommendations of up to 5000 characters.')
    grade = _locked_grade(grade)
    from .defense_workflow import require_current, is_chair, audit
    require_current(grade)
    if review_token is not None and review_token != outcome_payload(grade)['review_token']:
        raise ValidationError('The assessment changed. Refresh before saving recommendations.')
    if not is_chair(grade, actor):
        raise PermissionError('Only the assigned panel chair can save team recommendations.')
    reason = recommendations_unavailable_reason(grade, actor)
    if reason:
        raise ValidationError(reason)
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).first()
    following = ConceptRound.objects.filter(team_id=grade.team_id, project_version=grade.project_version,
        **({'defense_stage_id': grade.defense_stage_id} if grade.defense_stage_id else {}),
        number=hearing.number + 1).first() if hearing else None
    notes = notes.strip()
    grade.verdict_remarks = notes
    grade.outcome_metadata = {**grade.outcome_metadata, 'recommendations_by': actor.pk}
    grade.save(update_fields=['verdict_remarks', 'outcome_metadata', 'updated_at'])
    if hearing:
        hearing.remarks = notes
        hearing.save(update_fields=['remarks'])
    if following:
        concepts = deepcopy(following.concepts)
        for concept in concepts:
            concept['panel_feedback'] = notes
        following.concepts = concepts
        following.save(update_fields=['concepts'])
    audit(grade, actor, 'defense.recommendations_saved', recommendations=notes)
    from realtime.broadcast import notify_capstone_evaluation_flags
    transaction.on_commit(lambda: notify_capstone_evaluation_flags(grade.semester))
    return grade
