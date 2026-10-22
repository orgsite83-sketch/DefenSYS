"""Inspect active PIT/Capstone setup, completion gates and existing-account GETs.

PostgreSQL READ ONLY prevents writes, including writes attempted by API reads.
No logins, credentials, submissions, notifications or workflow changes are made.
Detailed, regenerable evidence is saved under .tmp/.
"""
import json
import os
from collections import Counter
from pathlib import Path
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def collect():
    from django.contrib.auth import get_user_model
    from django.db import transaction
    from django.urls import resolve
    from rest_framework.test import APIRequestFactory, force_authenticate
    from academic_period_management.models import Semester
    from defense.scheduler.models import PitEventGradingConfig
    from defense.stages.models import DefenseStage, StageGradingConfig
    from defense.stages.readiness import stage_setup_readiness
    from defensys_backend.read_projection import read_projection
    from grading.grades.models import TeamGrade
    from grading.grades.services import group_completion_readiness
    from repository.deliverables.services import stage_payload
    from student_teams.models import StudentTeam
    from user_management.models import SectionInstructorAssignment

    result = {'mode': 'read_only', 'setup': [], 'groups': [], 'teams': [], 'api_reads': [], 'errors': []}
    semesters = list(Semester.objects.filter(is_active=True))
    result['active_semester_count'] = len(semesters)
    if len(semesters) != 1:
        result['errors'].append({'surface': 'active_semester', 'reason': 'Expected exactly one active semester.'})
        return result
    semester = semesters[0]
    result['semester'] = semester.display_name
    teams = StudentTeam.objects.filter(semester=semester)
    result['team_counts'] = dict(Counter(t.level for t in teams))
    admin = get_user_model().objects.filter(role='admin', is_active=True).order_by('pk').first()
    events = list(PitEventGradingConfig.objects.filter(semester=semester).select_related('panel_rubric', 'peer_rubric'))
    stages = list(DefenseStage.objects.filter(is_active=True).order_by('display_order'))
    for stage in stages:
        config = StageGradingConfig.objects.filter(semester=semester, defense_stage=stage).first()
        result['setup'].append({'scope': 'capstone', 'label': stage.label,
            **stage_setup_readiness(stage, config, semester)})
    for event in events:
        issues = []
        if event.panel_weight + event.peer_weight != 100:
            issues.append('Grade weights must total 100%.')
        for role in ('panel', 'peer'):
            if not getattr(event, f'{role}_weight') or role == 'peer' and not event.peer_grading_enabled:
                continue
            rubric = getattr(event, f'{role}_rubric')
            if rubric is None or rubric.status != 'published' or rubric.scope != 'pit' or rubric.evaluation_type != role:
                issues.append(f'Attach a published PIT {role} rubric.')
        result['setup'].append({'scope': 'pit', 'label': event.event_name,
            'year_level': event.year_level, 'ready': not issues, 'issues': issues})
    if admin:
        for scope, label in [('pit', e.event_name) for e in events] + [('capstone', s.label) for s in stages]:
            try:
                with transaction.atomic(), read_projection():
                    readiness = group_completion_readiness(semester=semester, scope=scope, stage_label=label, user=admin)
                result['groups'].append({'scope': scope, 'label': label, **readiness})
            except Exception as error:
                result['errors'].append({'surface': 'completion', 'scope': scope, 'label': label,
                    'type': type(error).__name__, 'reason': str(error)})
    grades = TeamGrade.objects.filter(semester=semester).select_related('team', 'schedule', 'defense_stage', 'pit_event_config')
    seen = set()
    for grade in grades:
        label = grade.defense_stage.label if grade.defense_stage_id else grade.stage_label
        key = (grade.team_id, label)
        if key in seen:
            continue
        seen.add(key)
        try:
            with transaction.atomic(), read_projection():
                state = stage_payload(grade.team, label, evaluator=grade.team.leader)
                result['teams'].append({'team_id': grade.team_id, 'team_name': grade.team.name,
                    'scope': grade.scope, 'label': label, 'grade_status': grade.status,
                    'stage_status': state['stage_status_detail'], 'assessment': state['assessment_progress'],
                    'required_complete': state['required_complete'], 'endorsed': state['endorsed'],
                    'post_defense_ready': state['post_defense_ready'], 'post_unavailable_reason': state['post_unavailable_reason'],
                    'archive_complete': state['archive_complete'],
                    'documentation_complete': state['documentation_complete'],
                    'minutes_required': state['minutes_required'],
                    'materials_readiness': state['materials_readiness'],
                    'post': [{'id': d['id'], 'label': d['label'], 'can_upload': d['can_upload'],
                        'can_faculty_review': d['can_faculty_review'], 'uploaded': d['uploaded']} for d in state['post']]})
        except Exception as error:
            result['errors'].append({'surface': 'team_deliverables', 'team_id': grade.team_id,
                'label': label, 'type': type(error).__name__, 'reason': str(error)})

    actors = []
    if admin:
        actors.append(('admin', admin, [
            '/api/teams/?workspace=operations', '/api/defense/board/?workspace=operations',
            '/api/defense/schedules/?workspace=operations', '/api/grading/grades/?workspace=operations&scope=all',
            '/api/repository/deliverables/?workspace=operations&scope=capstone',
            '/api/repository/audit/?open_current_semester=1']))
    for year in sorted({event.year_level for event in events}):
        lead = get_user_model().objects.filter(role='faculty', is_active=True, is_pit_lead=True, pit_lead_year=year).first()
        if lead:
            actors.append((f'pit_lead_{year}', lead, ['/api/defense/board/?workspace=operations',
                '/api/grading/grades/?workspace=operations&scope=pit', '/api/repository/deliverables/?workspace=operations&scope=pit']))
    assignment = SectionInstructorAssignment.objects.filter(semester=semester, is_active=True, faculty__is_active=True).select_related('faculty').first()
    if assignment:
        actors.append(('instructor', assignment.faculty, ['/api/repository/deliverables/?workspace=instructor&scope=pit']))
    for scope in ('pit', 'capstone'):
        team = next((t for t in teams if t.is_capstone == (scope == 'capstone')), None)
        if team:
            actors.append((f'{scope}_student', team.leader, ['/api/repository/deliverables/', '/api/teams/my-setup/']))
            if scope == 'capstone' and team.adviser_id:
                actors.append(('adviser', team.adviser, ['/api/repository/deliverables/?workspace=adviser&scope=capstone',
                    '/api/grading/grades/adviser-grades/']))
    panelist = get_user_model().objects.filter(is_active=True, is_panelist=True).first()
    if panelist:
        actors.append(('panelist', panelist, ['/api/defense/schedules/panelist-assignments/', '/api/defense/schedules/panelist-results/']))
    factory = APIRequestFactory()
    for role, actor, paths in actors:
        for path in paths:
            try:
                with transaction.atomic():
                    request = factory.get(path)
                    force_authenticate(request, user=actor)
                    match = resolve(urlsplit(path).path)
                    response = match.func(request, *match.args, **match.kwargs)
                    response.render()
                    result['api_reads'].append({'role': role, 'actor_id': actor.pk, 'path': path, 'status': response.status_code})
            except Exception as error:
                result['errors'].append({'surface': 'api_read', 'role': role, 'path': path,
                    'type': type(error).__name__, 'reason': str(error)})
    return result


def main():
    import django
    django.setup()
    from django.db import connection, transaction
    if connection.vendor != 'postgresql':
        raise RuntimeError('PostgreSQL READ ONLY enforcement is required.')
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        result = collect()
    output = ROOT / '.tmp' / 'active-workflow-audit.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2, default=str), encoding='utf-8')
    print(json.dumps({'output': str(output), 'semester': result.get('semester'),
        'team_counts': result.get('team_counts'), 'setup_issues': [s for s in result['setup'] if not s['ready']],
        'team_projections': len(result['teams']), 'api_reads': len(result['api_reads']),
        'api_failures': [r for r in result['api_reads'] if r['status'] != 200], 'errors': result['errors']}))


if __name__ == '__main__':
    main()
