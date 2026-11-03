"""The chair chooses preparation; existing services own titles, files and grades."""
from copy import deepcopy
from hashlib import sha256
import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import F

from defensys_backend.read_projection import read_memoize
from .models import SharedModuleRedefenseDecision as Decision

_NO_RECOMMENDATIONS = object()


def independent_team_ids():
    return Decision.objects.filter(direction=Decision.INDEPENDENT,
        source_round__project_version=F('source_round__team__project_version')
    ).values_list('source_round__team_id', flat=True)


@read_memoize
def independent(team):
    """Current direction follows the project; historical term adapters use snapshots."""
    if not team.is_capstone:
        return False
    recorded = getattr(team, '_recorded_term', None)
    if recorded:
        return recorded.snapshot.get('project_direction') == Decision.INDEPENDENT
    return Decision.objects.filter(direction=Decision.INDEPENDENT,
        source_round__team_id=team.pk, source_round__project_version=team.project_version).exists()


def _context(grade):
    from repository.deliverables.models import ConceptRound
    from grading.grades.outcome_rules import automatic_outcomes
    if (not grade.schedule_id or not grade.is_capstone or
            not automatic_outcomes(grade.schedule) or grade.verdict != 'for_redefense'):
        return None
    source = ConceptRound.objects.filter(schedule_id=grade.schedule_id).select_related(
        'section_round__project__section__semester', 'section_round__project__project_manager').first()
    if not source or not source.section_round_id or not source.section_round.selected_key:
        return None
    following = ConceptRound.objects.filter(team_id=grade.team_id, project_version=grade.project_version,
        defense_stage_id=grade.defense_stage_id, number=source.number + 1).first()
    decision = Decision.objects.filter(source_round=source).select_related('decided_by').first()
    return source, following, decision


def _unavailable(grade, source, following):
    from grading.grades.defense_workflow import require_current
    from grading.grades.automatic_outcomes import recommendations_unavailable_reason
    from student_teams.services import was_stage_endorsed
    from . import services
    if grade.closed_as_failed or grade.status in grade.LOCKED_STATUSES:
        return 'This result is finalized. Use the existing correction process.'
    try:
        require_current(grade)
        services.require_active(source.section_round.project)
    except (ValidationError, PermissionError) as error:
        return ' '.join(error.messages) if isinstance(error, ValidationError) else str(error)
    if grade.semester_id != grade.team.semester_id:
        return 'This assessment belongs to an earlier academic period.'
    if not services.active_links(source.section_round.project).filter(team_id=grade.team_id).exists():
        return 'The shared membership changed. Review the current assignment first.'
    from grading.grades.outcome_rules import outcome_payload
    assessment = outcome_payload(grade)
    if (source.verdict != 'for_redefense' or not assessment or not assessment['panel_complete']
            or assessment['outcome'] != 'for_redefense'):
        return 'The linked-module assessment changed. Review its complete result first.'
    if not following or following.schedule_id or following.verdict:
        return 'The next attempt has started or is unavailable. Refresh the assessment.'
    if following.endorsed_at or was_stage_endorsed(grade.team, grade.defense_stage):
        return 'The next attempt is endorsed. Review its preparation before changing direction.'
    if services.latest(source.section_round.project).pk != source.section_round_id:
        return 'The shared proposal round changed. Refresh the assessment.'
    # Readiness after a score-derived outcome is deliberately independent of
    # recommendations text. The assigned chair is checked separately.
    reason = recommendations_unavailable_reason(grade, _chair(grade))
    return reason


def _chair(grade):
    row = grade.schedule.panel_assignments.select_related('panelist').filter(is_chair=True).first()
    return row.panelist if row else None


def _independent_unavailable(grade, source):
    from . import services
    if grade.defense_stage.concept_config.get('required_count', 3) != 3:
        return 'This route requires three independent concepts in the stage configuration.'
    project = source.section_round.project
    remaining = services.active_links(project).exclude(team_id=grade.team_id)
    if remaining.exists():
        from django.db.models import Q
        if not remaining.filter(Q(team__leader_id=project.project_manager_id) |
                Q(team__memberships__student_id=project.project_manager_id)).exists():
            return 'Assign an eligible remaining shared project manager in Manage sections before this team becomes independent.'
    return ''


def _preparation(following):
    from repository.deliverables.models import ConceptRevisionRequest, DeliverableSubmissionFile
    value = {
        'id': following.pk, 'section_round_id': following.section_round_id,
        'number': following.number, 'concepts': deepcopy(following.concepts),
        'policy_snapshot': deepcopy(following.policy_snapshot),
        'title_workflow_version': following.title_workflow_version,
        'schedule_id': following.schedule_id,
        'endorsed_at': str(following.endorsed_at) if following.endorsed_at else None,
        'title_requests': list(ConceptRevisionRequest.objects.filter(concept_round=following)
            .values('id', 'concept_key', 'title_snapshot', 'feedback', 'requested_by_id')),
        'files': list(DeliverableSubmissionFile.objects.filter(
            submission__team_id=following.team_id,
            submission__project_version=following.project_version,
            submission__stage_label=following.defense_stage.label)
            .order_by('pk').values('id', 'revision', 'is_current', 'status', 'file_name',
                'concept_round_id', 'title_review_context', 'reviewed_at', 'reviewed_by_id')),
    }
    return json.loads(json.dumps(value, default=str))


def _token(grade, source, following, decision):
    from . import services
    value = [grade.pk, grade.schedule_id, str(grade.updated_at), source.pk, source.verdict,
        services.review_token(source.section_round), _preparation(following) if following else None,
        grade.defense_stage.concept_config, decision.pk if decision else None,
        source.section_round.project.project_manager_id,
        list(services.active_links(source.section_round.project).order_by('team_id').values_list('team_id', flat=True))]
    return sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def payload(grade, actor=None):
    context = _context(grade)
    if not context:
        return None
    source, following, decision = context
    from grading.grades.defense_workflow import is_chair
    reason = _unavailable(grade, source, following) if not decision else ''
    allowed = bool(actor and is_chair(grade, actor))
    from . import services
    preparation = _preparation(following) if following else {}
    selected = source.section_round.selected_key
    return {
        'source_round_id': source.pk, 'next_round_id': following.pk if following else None,
        'direction': decision.direction if decision else '',
        'decided_by': decision.decided_by.get_full_name() or decision.decided_by.username if decision else '',
        'decided_at': decision.decided_at.isoformat() if decision else None,
        'can_decide': bool(allowed and not reason and not decision),
        'unavailable_reason': reason if allowed else '',
        'independent_unavailable_reason': _independent_unavailable(grade, source) if allowed and not decision else '',
        'review_token': _token(grade, source, following, decision) if allowed else '',
        'impact': {
            'team': grade.team.name,
            'shared_system': source.section_round.systems.filter(key=selected).values_list('title', flat=True).first() or '',
            'module': next((c.get('title', '') for c in source.concepts if c['key'] == selected), ''),
            'next_attempt': following.number if following else None,
            'saved_titles': sum(bool(c.get('title', '').strip()) for c in preparation.get('concepts', [])),
            'saved_files': sum(bool(f['is_current']) for f in preparation.get('files', [])),
            'remaining_teams': list(services.active_links(source.section_round.project).exclude(
                team_id=grade.team_id).order_by('team_id').values_list('team__name', flat=True)),
        } if allowed and not decision else {},
    }


@transaction.atomic
def confirm(grade, *, actor, direction, source_round_id, review_token,
            recommendations=_NO_RECOMMENDATIONS):
    from grading.grades.automatic_outcomes import _locked_grade
    from grading.grades.defense_workflow import is_chair, audit
    from repository.deliverables.models import ConceptRound
    from repository.deliverables.redefense import refresh_files
    from student_teams.concept_policy import initial_concepts
    # Shared writers lock the project/round before the participating teams.
    # Use the same order for parallel route decisions and title/roster edits.
    initial = _context(grade)
    if not initial:
        raise ValidationError('This assessment has no eligible shared-module re-defense.')
    from .models import SectionConceptProject, SectionConceptRound
    SectionConceptProject.objects.select_for_update().get(pk=initial[0].section_round.project_id)
    SectionConceptRound.objects.select_for_update().get(pk=initial[0].section_round_id)
    grade = _locked_grade(grade)
    if not is_chair(grade, actor):
        raise PermissionError('Only the assigned panel chair can decide the next-attempt direction.')
    if direction not in (Decision.SHARED, Decision.INDEPENDENT):
        raise ValidationError('Choose shared-module revision or three independent concepts.')
    context = _context(grade)
    if not context:
        raise ValidationError('This assessment has no eligible shared-module re-defense.')
    source, following, recorded = context
    if source.section_round_id != initial[0].section_round_id:
        raise ValidationError('The shared hearing changed. Refresh before confirming.')
    if source.pk != source_round_id:
        raise ValidationError('The assessed attempt changed. Refresh before confirming.')
    if recorded:
        if recorded.direction != direction:
            raise ValidationError('The chair decision is already recorded. Use the correction process to change it.')
        return grade
    if following:
        following = ConceptRound.objects.select_for_update().get(pk=following.pk)
    reason = _unavailable(grade, source, following)
    if reason:
        raise ValidationError(reason)
    if review_token != _token(grade, source, following, None):
        raise ValidationError('The next-attempt preparation changed. Refresh and review it again.')
    if direction == Decision.INDEPENDENT:
        reason = _independent_unavailable(grade, source)
        if reason:
            raise ValidationError(reason)
    from grading.grades.outcome_rules import outcome_payload
    before = _preparation(following)
    decision = Decision.objects.create(source_round=source, next_round=following,
        source_grade=grade, direction=direction, decided_by=actor,
        assessment_snapshot={'schedule_id': grade.schedule_id, 'verdict': grade.verdict,
            'project_title': grade.project_title_snapshot, 'assessment': outcome_payload(grade)},
        preparation_snapshot=before)
    if direction == Decision.INDEPENDENT:
        # This is the existing unassessed preparation, not the earlier hearing.
        # Keep its previous title/review/file identities in the immutable decision.
        policy = deepcopy(grade.defense_stage.concept_config)
        policy.update(mode='proposals', required_count=3, concept_keys=['c1', 'c2', 'c3'],
            assigned_title='', seed_title='', source='chair_independent',
            source_round_id=source.pk, direction_decision_id=decision.pk)
        following.section_round = None
        following.policy_snapshot = policy
        following.concepts = initial_concepts(policy)
        for concept in following.concepts:
            concept.update(title_review={'state': 'draft', 'version': 0},
                faculty_confirmed=False, requested_action='replace',
                panel_feedback=grade.verdict_remarks)
        following.title_workflow_version = max(2, following.title_workflow_version)
        following.review_required = True
        following.endorsement_snapshot = []
        following.save()
        grade.team.project_title = ''
        grade.team.project_pending = True
        grade.team._section_concept_projects = {}
        grade.team.save(update_fields=['project_title', 'project_pending', 'updated_at'])
        refresh_files(grade.team, grade.defense_stage)
    if recommendations is not _NO_RECOMMENDATIONS:
        from grading.grades.automatic_outcomes import save_recommendations
        # The reviewed direction was validated under these locks. Saving its
        # feedback here keeps both atomic and leaves idempotent retries above
        # unable to overwrite recommendations edited after confirmation.
        grade = save_recommendations(grade, actor=actor, notes=recommendations)
    audit(grade, actor, 'defense.redefense_direction_confirmed',
        direction=direction, source_round_id=source.pk, next_round_id=following.pk,
        decision_id=decision.pk)
    from realtime.broadcast import notify_capstone_evaluation_flags
    transaction.on_commit(lambda: notify_capstone_evaluation_flags(grade.semester))
    return grade
