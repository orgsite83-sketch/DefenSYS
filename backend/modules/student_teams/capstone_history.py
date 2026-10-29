"""Authorized, read-only intake history, including its open continuation."""
from copy import copy

from rest_framework import serializers

from .capstone_context import phase_for, phase_label, phase_requirements, stage_context
from .capstone_lifecycle import historical_payload, recorded_team, team_snapshot, term_key
from .participation import intake_for


def recorded_authority(user, row):
    if not row or not row.closed_at:
        return False
    snapshot = row.snapshot
    if getattr(user, 'role', None) == 'faculty':
        return snapshot.get('adviser_id') == user.pk
    if getattr(user, 'role', None) == 'student':
        return user.pk in snapshot.get('member_ids', []) or snapshot.get('leader_id') == user.pk
    return False


def history_teams_for(user, workspace=None):
    from authentication_access_control.workspaces import workspace_teams_for
    from django.db.models import Q
    from .models import StudentTeam, TeamTermParticipation
    base = workspace_teams_for(user, workspace)
    if workspace not in (None, '', 'adviser') or not user.is_authenticated:
        return base
    query = Q(pk__in=[])
    if user.role == 'faculty':
        query = Q(snapshot__adviser_id=user.pk)
    elif user.role == 'student':
        query = Q(snapshot__member_ids__contains=[user.pk]) | Q(snapshot__leader_id=user.pk)
    recorded = TeamTermParticipation.objects.filter(query, closed_at__isnull=False).values('team_id')
    return StudentTeam.objects.filter(Q(pk__in=base.values('pk')) | Q(pk__in=recorded))


def _history_identity(team, term, row):
    """Fields used to filter/group setup history, without loading team evidence."""
    from .serializers import display_name
    if row and row.closed_at:
        data = dict(row.snapshot)
        data['status'] = {'completed': 'Completed', 'failed': 'Failed',
            'needs_review': 'Needs review'}.get(row.outcome, data.get('status', 'Pending'))
    else:
        data = {field: getattr(team, field) for field in (
            'name', 'project_title', 'year_level', 'section', 'status')}
        data.update(leader_name=display_name(team.leader), adviser_name=display_name(team.adviser))
    return {**data, 'semester_id': term.pk, 'display_semester': term.display_name}


def _matches_history_filters(data, params):
    if params.get('semester_id') and str(data['semester_id']) != params['semester_id']:
        return False
    if any(params.get(k) and str(data.get(k, '')) != params[k] for k in ('year_level', 'section', 'status')):
        return False
    search = params.get('search', '').casefold()
    return not search or search in ' '.join(str(data.get(k, '')) for k in (
        'name', 'project_title', 'leader_name', 'adviser_name')).casefold()


def history_payload(visible, params, *, user=None, include_details=True):
    """Setup directories only need authorized phase/stage identities, not dossiers."""
    from .models import TeamTermParticipation
    from user_management.academic_records.models import StudentAcademicRecord
    teams = list(visible.filter(level__icontains='Capstone').select_related(
        'semester__school_year', 'intake_semester__school_year', 'leader', 'adviser').distinct())
    live_authority = None
    if user is not None:
        from authentication_access_control.workspaces import workspace_teams_for
        live_authority = set(workspace_teams_for(user, params.get('workspace')).values_list('pk', flat=True))
    intakes = {}
    by_intake = {}
    for team in teams:
        intake = intake_for(team)
        if intake:
            intakes[intake.pk] = intake
            by_intake.setdefault(intake.pk, []).append(team)
    choices = sorted(intakes.values(), key=term_key, reverse=True)
    selected = serializers.IntegerField(min_value=1).run_validation(params['intake_id']) if params.get('intake_id') else (choices[0].pk if choices else None)
    phase = params.get('phase', '')
    stage_key = params.get('stage_key', '')
    options = {'intakes': [{'id': t.pk, 'label': f'Intake: {t.display_name}'} for t in choices],
        'selected_intake_id': selected, 'phases': [], 'stages': []}
    records, stages, phases = [], {}, {}
    for team in by_intake.get(selected, []):
        rows = list(TeamTermParticipation.objects.filter(team=team).select_related('semester__school_year'))
        contexts = [(r.semester, r) for r in rows]
        if not any(r.semester_id == team.semester_id for r in rows):
            contexts.append((team.semester, None))
        for term, row in sorted(contexts, key=lambda pair: term_key(pair[0])):
            if live_authority is not None and team.pk not in live_authority and not recorded_authority(user, row):
                continue
            if row and not row.closed_at and term.pk != team.semester_id:
                continue
            context = recorded_team(team, term) if row and row.closed_at else team
            # Only a confirmed intake or its linked continuation belongs here.
            value = phase_for(team, term)
            if value == 'needs_review':
                continue
            label = phase_label(value)
            phases[value] = {'value': value, 'label': label}
            requirements = phase_requirements(context)
            for requirement in requirements:
                key = f'{term.pk}:{requirement["id"]}'
                stages[key] = {'value': key, 'id': requirement['id'], 'semester_id': term.pk,
                    'phase': value, 'label': f'{label} · {requirement["label"]} · {term.display_name}'}
            if phase and phase != value:
                continue
            selected_requirement = next((r for r in requirements if f'{term.pk}:{r["id"]}' == stage_key), None)
            if stage_key and not selected_requirement:
                continue
            if not include_details:
                data = _history_identity(context, term, row)
                data.update(phase=value, phase_label=label, record_key=f'{team.pk}:{term.pk}',
                    stage_requirements=requirements)
                if _matches_history_filters(data, params):
                    records.append(data)
                continue
            data = historical_payload(row) if row and row.closed_at else team_snapshot(context)
            projection = copy(context)
            if selected_requirement:
                projection.current_defense_stage = selected_requirement['label']
                projection._selected_history_stage = True
                projection._projection_context = {'selected_stage': selected_requirement['id']}
            data['defense_context'] = stage_context(projection)
            data['stage_requirements'] = requirements
            data.update(phase=value, phase_label=label, record_key=f'{team.pk}:{term.pk}',
                intake_id=selected, term_status='historical', is_editable=False,
                phase_is_open=not bool(row and row.closed_at),
                current_defense_stage=data['defense_context']['current_stage'],
                deliverable_count=data['defense_context']['deliverable_count'])
            from grading.grades.models import TeamGrade
            assessments = TeamGrade.all_objects.filter(team=team, semester=term)
            if user is not None and not recorded_authority(user, row):
                from authentication_access_control.scopes import grade_records_for
                assessments = assessments.filter(pk__in=grade_records_for(
                    user, include_previous_projects=True).values('pk'))
            if getattr(user, 'role', None) == 'student':
                assessments = assessments.filter(status='published')
            if selected_requirement:
                assessments = assessments.filter(defense_stage_id=selected_requirement['id'])
            data['assessments'] = list(assessments.order_by('project_version', 'pk').values(
                'id', 'project_version', 'project_title_snapshot', 'defense_stage_id',
                'stage_label', 'status', 'verdict', 'final_grade'))
            from .history_events import timeline_for
            data['timeline'] = timeline_for(team, term,
                stage_id=selected_requirement['id'] if selected_requirement else None,
                stage_label=selected_requirement['label'] if selected_requirement else None,
                stage_ids=[r['id'] for r in requirements])
            from repository.deliverables.models import DeliverableSubmission
            files = DeliverableSubmission.all_objects.filter(team=team, archive_semester=term,
                project_version=context.project_version,
                stage_label=data['defense_context']['current_stage'])
            if getattr(user, 'role', None) == 'student':
                restricted = [d['deliverable_id'] for r in requirements
                    for d in r.get('definitions', []) if d.get('is_restricted')]
                files = files.exclude(deliverable_id__in=restricted)
            data['files'] = list(files.order_by('pk').values('id', 'label', 'stage_label',
                'file_name', 'status', 'project_version', 'uploaded_at'))
            enrolled = set(StudentAcademicRecord.objects.filter(semester=term,
                student_id__in=data.get('member_ids', [])).values_list('student_id', flat=True))
            data['members'] = [{**m, 'id': m.get('student_id', m.get('id')),
                'is_enrolled': m.get('student_id', m.get('id')) in enrolled} for m in data.get('members', [])]
            if not _matches_history_filters(data, params):
                continue
            records.append(data)
    options['phases'] = sorted(phases.values(), key=lambda p: p['value'])
    options['stages'] = [s for s in stages.values() if not phase or s['phase'] == phase]
    records.sort(key=lambda r: (r['phase'], r.get('section', ''), r['name'], r['record_key']))
    return {'teams': records, 'capstone_history': options}
