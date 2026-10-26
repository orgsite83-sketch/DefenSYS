"""Read imported shared proposals; activate them only when the PM saves titles."""
from copy import deepcopy
from hashlib import sha256
import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import F
from defensys_backend.read_projection import read_memoize

from student_teams.models import SectionAssignment, StudentTeam
from student_teams.concept_policy import contexts_for, context_key, initial_concepts, proposal_keys, resolve_policy
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound
from . import services
from .models import SectionConceptProject, SectionConceptRound, SectionProjectTeam, SectionSystemConcept


def source_context_key(team):
    assignment = team.concept_assignment or {}
    if assignment.get('project_version', 1) != team.project_version:
        return None
    if assignment.get('context_key'):
        return assignment['context_key']
    first = contexts_for(team).first()
    return assignment.get('context_key') or (context_key(first) if first else None)


def context(team, label=''):
    supplied_context = source_context_key(team)
    if label:
        stage = concepts.stage_for(team, label)
    elif supplied_context:
        stage = contexts_for(team).filter(pk=int(supplied_context.split(':')[1])).first()
    else:
        stage = None
    if not concepts.enabled(stage):
        raise ValidationError('Enable concept selection for this stage first.')
    concepts.require_context(team, stage)
    if supplied_context != context_key(stage) and not services.project_for(team, stage):
        raise ValidationError('The imported system belongs to another concept hearing.')
    return stage


@read_memoize
def _section_title(semester_id, section, year_level):
    return SectionAssignment.objects.filter(semester_id=semester_id, section=section,
        year_level=year_level, project_manager__isnull=False).exclude(system_name='').first()


def system_titles(team, stage, policy):
    """Informational import slots, bound to this project version and hearing."""
    if policy.get('system_concepts'):
        return policy['system_concepts']
    if source_context_key(team) != context_key(stage):
        return []
    assignment = _section_title(team.semester_id, team.section, team.year_level)
    if not assignment:
        return []
    keys = policy.get('concept_keys') or proposal_keys(policy['required_count'])
    return [{'key': key, 'title': assignment.system_name if i == 0 else ''} for i, key in enumerate(keys)]


def imported_state(team, stage):
    assignment = SectionAssignment.objects.select_related('semester', 'project_manager').filter(
        semester_id=team.semester_id, section=team.section, year_level=team.year_level).first()
    if not assignment or not assignment.system_name.strip() or not assignment.project_manager_id:
        raise ValidationError('This section needs an imported system name and an assigned project manager.')
    teams = list(StudentTeam.objects.filter(semester_id=team.semester_id, section=team.section,
        year_level=team.year_level, level=team.level).select_related('leader', 'adviser', 'semester')
        .prefetch_related('memberships__student').order_by('pk'))
    if team.is_pit:
        from defense.scheduler.event_scope import pit_events_for_team
        teams = [t for t in teams if pit_events_for_team(t).filter(pk=stage.pk).exists()]
    if not teams or team.pk not in {t.pk for t in teams}:
        raise PermissionError('Choose a participating team in this section.')
    reviewer_ids = sorted({t.adviser_id for t in teams if t.adviser_id and t.adviser.is_active})
    if team.is_pit:
        from user_management.models import SectionInstructorAssignment
        reviewer_ids = list(SectionInstructorAssignment.objects.filter(semester_id=team.semester_id,
            section=team.section, year_level=team.year_level, is_active=True,
            faculty__is_active=True).values_list('faculty_id', flat=True).distinct())
    rounds = {r.team_id: r for r in ConceptRound.objects.filter(team_id__in=[t.pk for t in teams],
        project_version=F('team__project_version'),
        **services.context_fields(stage)).order_by('number', 'pk')}
    keys = proposal_keys(stage.concept_config.get('required_count', 3))
    blocker = ''
    rows, versions = [], []
    for t in teams:
        current = rounds.get(t.pk)
        if current and current.project_version != t.project_version:
            current = None
        values = deepcopy(current.concepts) if current else initial_concepts(resolve_policy(t, stage))
        if source_context_key(t) != context_key(stage):
            blocker = 'The section includes another project or concept context. Ask the administrator to review its participating teams.'
        if current and (current.number != 1 or current.schedule_id or current.verdict or current.endorsed_at
                or current.section_round_id or [c['key'] for c in values] != keys):
            blocker = 'Existing reviewed or scheduled concept work needs administrator review before shared setup.'
        if t.ready_for_stage == stage.label:
            blocker = 'Endorsed concept work needs administrator review before shared setup.'
        rows.append({'id': t.pk, 'name': t.name, 'leader_id': t.leader_id,
            'leader_name': (t.leader.get_full_name() or t.leader.username) if t.leader else '',
            'members': [{'id': m.student_id, 'name': m.student.get_full_name() or m.student.username,
                'is_leader': m.student_id == t.leader_id} for m in t.memberships.all()],
            'concepts': values, 'verdict': '', 'schedule_id': None})
        versions.append({'id': t.pk, 'version': t.project_version, 'adviser': t.adviser_id,
            'supplied_context': source_context_key(t),
            'round': current.pk if current else None, 'concepts': values,
            'schedule': current.schedule_id if current else None,
            'endorsed': str(current.endorsed_at) if current else '', 'ready': t.ready_for_stage,
            'verdict': current.verdict if current else ''})
    if not concepts.title_context_is_open(team, stage):
        blocker = 'Completed or historical shared concepts are read-only.'
    if not reviewer_ids:
        blocker = 'Assign the section advisers or instructor before proposing shared systems.'
    elif team.is_pit and len(reviewer_ids) != 1:
        blocker = 'Ask the section manager to choose the shared system reviewer before proposing these systems.'
    state = {'section_id': assignment.pk, 'system_name': assignment.system_name,
        'pm': assignment.project_manager_id, 'context': [type(stage).__name__, stage.pk],
        'keys': keys, 'teams': versions, 'reviewers': reviewer_ids}
    token = sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()
    return assignment, teams, rows, reviewer_ids, keys, blocker, token


def preview(team, stage, actor):
    project = services.project_for(team, stage)
    if project:
        return services.payload(project, actor)
    assignment, teams, rows, reviewer_ids, keys, blocker, token = imported_state(team, stage)
    from django.contrib.auth import get_user_model
    reviewers = [{'id': u.pk, 'name': u.get_full_name() or u.username}
        for u in get_user_model().objects.filter(pk__in=reviewer_ids).order_by('pk')]
    return {'id': None, 'imported': True, 'team_id': team.pk, 'section': assignment.section,
        'semester_id': team.semester_id, 'stage_label': stage.label, 'round': 1,
        'review_token': token, 'project_manager_id': assignment.project_manager_id,
        'project_manager_name': assignment.project_manager.get_full_name() or assignment.project_manager.username,
        'reviewers': reviewers, 'reviewer_name': ', '.join(r['name'] for r in reviewers),
        'selected_key': '', 'verdict': '', 'teams': rows,
        'systems': [{'key': k, 'title': assignment.system_name if i == 0 else '',
            'confirmed': False, 'papers': [], 'can_upload': bool(i == 0 and not blocker and
                actor.role == 'student' and actor.pk == assignment.project_manager_id)} for i, k in enumerate(keys)],
        'can_edit_names': bool(not blocker and actor.role == 'student' and actor.pk == assignment.project_manager_id),
        'setup_unavailable_reason': blocker, 'can_manage': False, 'can_review': False}


@transaction.atomic
def save(team, stage, actor, titles, token):
    # Lock the section before its complete team set; previews never create rows.
    SectionAssignment.objects.select_for_update().get(semester_id=team.semester_id,
        section=team.section, year_level=team.year_level)
    list(StudentTeam.objects.select_for_update().filter(semester_id=team.semester_id,
        section=team.section, year_level=team.year_level, level=team.level).order_by('pk'))
    stage = type(stage).objects.select_for_update().get(pk=stage.pk)
    if not concepts.enabled(stage):
        raise ValidationError('Concept selection was disabled. Refresh the section before saving.')
    if services.project_for(team, stage):
        raise ValidationError('Shared proposals were already opened. Refresh the section before saving.')
    assignment, teams, rows, reviewer_ids, keys, blocker, expected = imported_state(team, stage)
    if actor.role != 'student' or actor.pk != assignment.project_manager_id:
        raise PermissionError('Only the assigned section project manager can propose its shared systems.')
    if not token or token != expected:
        raise ValidationError('The section proposals changed. Refresh before saving.')
    if blocker:
        raise PermissionError(blocker)
    # The reviewer FK remains the contact; all participating Capstone advisers
    # receive shared paper review access through services.is_reviewer().
    project = SectionConceptProject.objects.create(section=assignment, **services.context_fields(stage),
        project_manager=assignment.project_manager, reviewer_id=reviewer_ids[0], title_mode='student_proposed')
    services.require_active(project)
    shared_round = SectionConceptRound.objects.create(project=project)
    SectionSystemConcept.objects.bulk_create([SectionSystemConcept(round=shared_round, key=k,
        title=assignment.system_name if i == 0 else '') for i, k in enumerate(keys)])
    for t in teams:
        SectionProjectTeam.objects.create(project=project, team=t, project_version=t.project_version)
        t._section_concept_projects = {}
        current = concepts.latest_round(t, stage)
        if current:
            current.section_round = shared_round
            current.policy_snapshot = services.policy_for(t, stage)
            current.save(update_fields=['section_round', 'policy_snapshot'])
        t.project_pending = True
        t.save(update_fields=['project_pending', 'updated_at'])
    if titles is not None:
        services.save_system_titles(project, actor, titles)
    services.audit(actor, 'imported_proposals_opened', project, team_ids=[t.pk for t in teams],
        imported_system=assignment.system_name, reviewer_ids=reviewer_ids)
    return project
