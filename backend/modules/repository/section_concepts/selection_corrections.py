"""Chair corrections to an open shared choice, preserving each proposal's evidence."""
from hashlib import sha256
import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from defensys_backend.read_projection import read_memoize
from . import services


def _context(round):
    from repository.deliverables.models import ConceptRound
    from grading.grades.models import TeamGrade
    schedules = list(round.schedules.select_related('team', 'semester', 'defense_stage', 'rubric').order_by('pk'))
    hearings = {r.schedule_id: r for r in ConceptRound.objects.filter(section_round=round).select_related('team')}
    grades = {g.schedule_id: g for g in TeamGrade.objects.filter(schedule__in=schedules).select_related(
        'team', 'schedule__rubric', 'semester', 'defense_stage')}
    return schedules, hearings, grades


def _chair(schedules, actor):
    return bool(actor and not getattr(actor, 'is_guest_panelist', False) and schedules and all(
        s.panel_assignments.filter(panelist=actor, is_chair=True).exists() for s in schedules))


def _unavailable(round, context):
    from repository.deliverables.models import ConceptRound
    from grading.grades.defense_workflow import require_current
    from grading.grades.outcome_rules import automatic_outcomes
    from defense.scheduler.panelist_evaluation import roster_unavailable_reason
    schedules, hearings, grades = context
    if round.project.pit_event_config_id:
        return 'Shared selection correction is available for Capstone hearings.'
    try:
        services.require_active(round.project)
    except (PermissionError, ValidationError) as error:
        return str(error)
    if services.latest(round.project).pk != round.pk:
        return 'This shared hearing is historical and read-only.'
    if not round.selected_key or round.verdict not in ('approved', 'approved_with_revisions'):
        return 'Confirm a shared system before correcting its selection.'
    expected = set(services.active_links(round.project).values_list('team_id', flat=True))
    recorded = {row['team_id'] for row in round.decision_snapshot.get('teams', [])}
    if (not expected or not schedules or {s.team_id for s in schedules} != expected
            or (recorded and recorded != expected)):
        return 'The participating teams changed. Review their existing results first.'
    if round.revisions_cleared_at or round.systems.filter(papers__purpose='final').exists():
        return 'Shared post-defense work has started. Review its recorded result before changing the selection.'
    from .models import SharedDeliverableSet
    for captured in SharedDeliverableSet.objects.filter(source_round=round):
        post_ids = [d['deliverable_id'] for d in captured.requirements if d.get('deliverable_type') == 'post']
        if captured.files.filter(deliverable_id__in=post_ids).exists():
            return 'Shared post-defense work has started. Review its recorded result before changing the selection.'
    for schedule in schedules:
        hearing, grade = hearings.get(schedule.pk), grades.get(schedule.pk)
        if not hearing or not grade:
            return 'Every participating team needs its current hearing and assessment.'
        if (grade.verdict or hearing.verdict or grade.closed_as_failed
                or grade.status in grade.LOCKED_STATUSES):
            return f'{schedule.team.name} already has a recorded outcome. Review the affected results before changing the shared system.'
        if (schedule.status != 'scheduled' or schedule.operation_state != 'normal'
                or schedule.semester_id != schedule.team.semester_id
                or schedule.project_version != schedule.team.project_version):
            return f'{schedule.team.name}: this hearing is no longer open for selection correction.'
        try:
            require_current(grade)
        except ValidationError as error:
            return ' '.join(error.messages)
        current = ConceptRound.objects.filter(team_id=hearing.team_id, project_version=hearing.project_version,
            defense_stage_id=hearing.defense_stage_id).order_by('-number', '-pk').first()
        if not current or current.pk != hearing.pk or grade.schedule_id != schedule.pk:
            return f'{schedule.team.name}: the current attempt changed.'
        if not automatic_outcomes(schedule) or schedule.assessment_policy.get('shared_module_scope_version') != 1:
            return 'Review and adopt selected-module grading for these captured hearings before correcting the selection.'
        if roster_unavailable_reason(schedule):
            return 'Correct the participating panel assignments before changing the shared selection.'
    return ''


def _token(round, context):
    from grading.grades.outcome_rules import outcome_payload
    schedules, hearings, grades = context
    state = [round.pk, round.selected_key, round.verdict, str(round.decided_at),
        round.decision_snapshot, services.review_token(round),
        [[s.pk, s.status, s.operation_state, s.revision, str(s.updated_at),
          hearings[s.pk].concepts, outcome_payload(grades[s.pk])['review_token'],
          list(s.evaluation_drafts.order_by('pk').values('pk', 'context_signature', 'updated_at', 'submissions'))]
         for s in schedules]]
    return sha256(json.dumps(state, sort_keys=True, default=str).encode()).hexdigest()


@read_memoize(copy=True)
def payload(round, actor):
    if round.project.pit_event_config_id:
        return {'can_correct': False, 'is_chair': False, 'unavailable_reason': '',
            'review_token': '', 'teams': [], 'history': []}
    context = _context(round)
    schedules, hearings, _ = context
    chair = _chair(schedules, actor)
    reason = _unavailable(round, context) if chair else ''
    keys = [s.key for s in round.systems.all()]
    return {
        'can_correct': bool(chair and not reason), 'is_chair': chair,
        'unavailable_reason': reason,
        'review_token': _token(round, context) if chair and not reason else '',
        'from_key': round.selected_key,
        'teams': [{'id': s.team_id, 'name': s.team.name,
            'module_titles': {c['key']: c['title'] for c in hearings[s.pk].concepts if c['key'] in keys}}
            for s in schedules if s.pk in hearings] if chair else [],
        'history': round.decision_snapshot.get('selection_corrections', []),
    }


def for_grade(grade, actor):
    from grading.grades.outcome_rules import automatic_outcomes
    if grade.scope != 'capstone' or not automatic_outcomes(grade.schedule):
        return None
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).select_related('section_round__project').first() if grade.schedule_id else None
    if not hearing or not hearing.section_round_id:
        return None
    round = hearing.section_round
    return {'id': round.project_id, 'round_id': round.pk, 'selected_key': round.selected_key,
        'systems': list(round.systems.values('key', 'title')),
        'selection_correction': payload(round, actor)}


@transaction.atomic
def correct(project, actor, *, concept_key, reason, review_token):
    round = services.locked_round(project)
    context = _context(round)
    if not _chair(context[0], actor):
        raise PermissionError('Only the common assigned panel chair can correct the shared selection.')
    if not isinstance(reason, str) or not reason.strip() or len(reason) > 5000:
        raise ValidationError('Record why the shared-system selection needs correction.')
    if concept_key == round.selected_key or not round.systems.filter(key=concept_key).exclude(title='').exists():
        raise ValidationError('Choose a different shared system from this hearing.')
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    list(StudentTeam.objects.select_for_update().filter(pk__in=[s.team_id for s in context[0]]).order_by('pk'))
    list(DefenseSchedule.objects.select_for_update().filter(pk__in=[s.pk for s in context[0]]).order_by('pk'))
    list(TeamGrade.objects.select_for_update().filter(schedule__in=context[0]).order_by('pk'))
    context = _context(round)
    blocker = _unavailable(round, context)
    if blocker:
        raise ValidationError(blocker)
    if not _chair(context[0], actor) or review_token != _token(round, context):
        raise ValidationError('The shared assessment changed. Refresh and review the affected teams again.')
    schedules, hearings, grades = context
    for hearing in hearings.values():
        if not any(c['key'] == concept_key and c.get('title', '').strip() for c in hearing.concepts):
            raise ValidationError('Every participating team needs its linked module for the corrected system.')
    before = {'selected_key': round.selected_key, 'verdict': round.verdict, 'remarks': round.remarks,
        'decided_by_id': round.decided_by_id, 'decided_at': str(round.decided_at),
        'systems': list(round.systems.values('key', 'title', 'decision', 'remarks'))}
    now = timezone.now()
    history = list(round.decision_snapshot.get('selection_corrections', []))
    history.append({'from_key': round.selected_key, 'to_key': concept_key,
        'reason': reason.strip(), 'by_id': actor.pk,
        'by_name': actor.get_full_name() or actor.username, 'at': now.isoformat(), 'previous_decision': before})
    round.systems.exclude(key=concept_key).update(decision='not_selected')
    round.systems.filter(key=concept_key).update(decision=round.verdict, remarks=round.remarks)
    round.selected_key, round.decided_by, round.decided_at = concept_key, actor, now
    round.decision_snapshot = {**round.decision_snapshot,
        'systems': list(round.systems.values('key', 'title', 'decision', 'remarks')),
        'selection_corrections': history}
    round.save(update_fields=['selected_key', 'decided_by', 'decided_at', 'decision_snapshot'])
    for schedule in schedules:
        title = next(c['title'] for c in hearings[schedule.pk].concepts if c['key'] == concept_key)
        StudentTeam.objects.filter(pk=schedule.team_id).update(project_title=title, project_pending=False, updated_at=now)
        grade = grades[schedule.pk]
        grade.project_title_snapshot = title
        grade.save(update_fields=['project_title_snapshot', 'updated_at'])
    services.audit(actor, 'selection_corrected', round, before=before, selected_key=concept_key,
        reason=reason.strip(), schedule_ids=[s.pk for s in schedules])
    from grading.grades.automatic_outcomes import resolve_outcome
    for grade in grades.values():
        resolve_outcome(grade)
    from realtime.broadcast import notify_capstone_evaluation_flags
    transaction.on_commit(lambda: notify_capstone_evaluation_flags(project.section.semester))
    return round
