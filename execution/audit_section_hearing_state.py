"""Read-only section workflow inspection, including failed dashboard projections."""
import argparse
import json
import os
from pathlib import Path
import sys
import traceback

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'backend'), str(ROOT / 'backend' / 'modules')]
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def collect_continuity(section):
    """Compare live section bindings with preserved links across term changes."""
    from django.db.models import Q
    from academic_period_management.models import SemesterTransitionLog
    from student_teams.models import SectionAssignment, StudentTeam, TeamTermParticipation
    from repository.deliverables.services import current_stage_for_team
    from repository.section_concepts.models import SectionConceptProject
    from repository.section_concepts import services

    teams = list(StudentTeam.objects.filter(section__iexact=section, semester__is_active=True)
        .select_related('semester__school_year').order_by('pk'))
    ids = [team.pk for team in teams]
    projects = SectionConceptProject.objects.filter(team_links__team_id__in=ids).distinct()
    assignments = SectionAssignment.objects.filter(
        Q(pk__in=projects.values('section_id')) |
        Q(section__iexact=section, semester__is_active=True))
    participations = list(TeamTermParticipation.objects.filter(team_id__in=ids)
        .select_related('semester__school_year').order_by('team_id', 'pk'))
    project_rows = []
    for project in projects.select_related('section__semester__school_year'):
        hearing = services.latest(project)
        project_rows.append({'id': project.pk, 'section_id': project.section_id,
            'section': project.section.section, 'year_level': project.section.year_level,
            'semester_id': project.section.semester_id,
            'period': project.section.semester.display_name,
            'defense_stage_id': project.defense_stage_id,
            'pit_event_config_id': project.pit_event_config_id,
            'active_team_ids': list(services.active_links(project).values_list('team_id', flat=True)),
            'team_links': list(project.team_links.values('team_id', 'project_version')),
            'round_id': hearing.pk if hearing else None,
            'selected_key': hearing.selected_key if hearing else '',
            'verdict': hearing.verdict if hearing else '',
            'systems': list(hearing.systems.values('key', 'title')) if hearing else []})
    return {'section': section, 'mode': 'database_enforced_read_only',
        'teams': [{'id': team.pk, 'name': team.name, 'section': team.section,
            'semester_id': team.semester_id, 'period': team.semester.display_name,
            'intake_semester_id': team.intake_semester_id, 'project_version': team.project_version,
            'stage': (stage := current_stage_for_team(team)),
            'shared_display': services.team_display(team, stage)} for team in teams],
        'assignments': list(assignments.order_by('pk').values('id', 'section', 'year_level',
            'semester_id', 'system_name', 'project_manager_id')),
        'linked_projects': project_rows,
        'participations': [{'id': row.pk, 'team_id': row.team_id,
            'semester_id': row.semester_id, 'period': row.semester.display_name,
            'project_version': row.project_version, 'section': row.snapshot.get('section'),
            'outcome': row.outcome, 'closed_at': row.closed_at, 'transition_id': row.transition_id,
            'continuation_sections': row.snapshot.get('continuation_sections')}
            for row in participations],
        'transitions': list(SemesterTransitionLog.objects.filter(
            pk__in={row.transition_id for row in participations if row.transition_id}).values(
                'id', 'operation', 'from_semester_id', 'to_semester_id', 'created_at'))}


def collect(section):
    from django.contrib.auth import get_user_model
    from django.db import transaction
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    from repository.deliverables.models import ConceptRound
    from repository.section_concepts.models import SectionConceptProject
    from repository.section_concepts import services
    from authentication_access_control.models import SystemAuditLog
    teams = StudentTeam.objects.filter(section__iexact=section, semester__is_active=True)
    ids = list(teams.values_list('pk', flat=True))
    projects = SectionConceptProject.objects.filter(section__section__iexact=section, section__semester__is_active=True)
    result = {'section': section, 'mode': 'read_only',
        'teams': list(teams.values('id', 'name', 'level', 'semester_id', 'status', 'project_version',
            'project_pending', 'project_title', 'current_defense_stage', 'ready_for_stage', 'leader_id', 'adviser_id')),
        'schedules': list(DefenseSchedule.objects.filter(team_id__in=ids).values('id', 'team_id', 'status',
            'scope', 'event_name', 'project_version', 'scheduled_date')),
        'grades': list(TeamGrade.all_objects.filter(team_id__in=ids).values('id', 'team_id', 'schedule_id',
            'stage_label', 'pit_event_config_id', 'status', 'verdict', 'project_version', 'panel_score', 'peer_score')),
        'team_rounds': list(ConceptRound.objects.filter(team_id__in=ids).values('id', 'team_id', 'number',
            'schedule_id', 'section_round_id', 'verdict', 'endorsed_at', 'concepts', 'endorsement_snapshot',
            'decided_at', 'decided_by_id', 'remarks', 'revisions_cleared_at', 'replacement_required',
            'documents_snapshot')),
        'projects': [], 'projection_errors': [],
        'recent_workflow_audit': list(SystemAuditLog.objects.filter(category__in=('scheduling', 'repository', 'grade_center'))
            .order_by('-id').values('id', 'action', 'target_type', 'target_id', 'created_at', 'reason')[:15])}
    actor_ids = set(teams.values_list('leader_id', flat=True)) | set(teams.values_list('adviser_id', flat=True))
    for project in projects:
        actor_ids.update((project.project_manager_id, project.reviewer_id))
        rounds = []
        for hearing in project.rounds.all():
            rounds.append({'id': hearing.pk, 'number': hearing.number, 'selected_key': hearing.selected_key,
                'verdict': hearing.verdict, 'presentation_started_at': hearing.presentation_started_at,
                'decided_at': hearing.decided_at, 'decided_by_id': hearing.decided_by_id,
                'chair_id': hearing.chair_id, 'decision_snapshot': hearing.decision_snapshot,
                'remarks': hearing.remarks, 'revisions_cleared_at': hearing.revisions_cleared_at,
                'schedule_ids': list(hearing.schedules.values_list('pk', flat=True)),
                'systems': list(hearing.systems.values('id', 'key', 'title', 'confirmed', 'decision', 'remarks')),
                'final_paper_count': sum(system.papers.filter(purpose='final').count() for system in hearing.systems.all()),
                'paper_count': sum(system.papers.count() for system in hearing.systems.all())})
        result['projects'].append({'id': project.pk, 'pit_event_config_id': project.pit_event_config_id,
            'defense_stage_id': project.defense_stage_id, 'rounds': rounds,
            'team_links': list(project.team_links.values('team_id', 'project_version'))})
        for actor in get_user_model().objects.filter(pk__in=actor_ids - {None}):
            try:
                payload = services.payload(project, actor)
                result['projects'][-1].setdefault('readable_actors', []).append(actor.pk)
            except Exception:
                result['projection_errors'].append({'project_id': project.pk, 'actor_id': actor.pk,
                    'surface': 'section_project', 'traceback': traceback.format_exc()})
    for actor in get_user_model().objects.filter(pk__in=actor_ids - {None}):
        try:
            services.task_payload(actor)
        except Exception:
            result['projection_errors'].append({'actor_id': actor.pk, 'surface': 'section_tasks',
                'traceback': traceback.format_exc()})
    from repository.deliverables.services import stage_payload
    from repository.deliverables.concepts import clearance_blocker, pit_ready
    result['readiness'] = []
    for team in teams:
        for project in projects.filter(team_links__team=team):
            try:
                with transaction.atomic():
                    state = stage_payload(team, project.context.label, evaluator=team.leader)
                    result['readiness'].append({'team_id': team.pk, 'status': state['stage_status_detail'],
                        'required_complete': state['required_complete'], 'endorsed': state['endorsed'],
                        'pit_ready': pit_ready(team, project.context), 'blocker': clearance_blocker(team, project.context)})
            except Exception:
                result['projection_errors'].append({'team_id': team.pk, 'surface': 'deliverable_stage',
                    'traceback': traceback.format_exc()})
    from rest_framework.test import APIClient
    result['api_statuses'] = []
    for actor in get_user_model().objects.filter(pk__in=actor_ids - {None}):
        client = APIClient()
        client.force_authenticate(actor)
        endpoints = ['/api/me/', '/api/teams/', '/api/teams/my-setup/',
            '/api/dashboards/student/' if actor.role == 'student' else '/api/dashboards/faculty/']
        for endpoint in endpoints:
            try:
                with transaction.atomic():
                    response = client.get(endpoint, HTTP_HOST='localhost')
                    result['api_statuses'].append({'actor_id': actor.pk, 'endpoint': endpoint, 'status': response.status_code})
            except Exception:
                result['projection_errors'].append({'actor_id': actor.pk, 'surface': endpoint,
                    'traceback': traceback.format_exc()})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--section', required=True)
    parser.add_argument('--continuity-only', action='store_true',
        help='Inspect live and source-term shared-system bindings without API probes.')
    args = parser.parse_args()
    import django
    django.setup()
    from django.db import connection, transaction
    from defensys_backend.read_projection import read_projection
    with transaction.atomic(), read_projection():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        result = collect_continuity(args.section) if args.continuity_only else collect(args.section)
    output = ROOT / '.tmp' / ('section-shared-continuity.json' if args.continuity_only else 'section-hearing-state.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, default=str), encoding='utf-8')
    if args.continuity_only:
        print(json.dumps({'output': str(output), **result}, default=str))
        return
    print(json.dumps({'output': str(output), 'teams': len(result['teams']),
        'projects': result['projects'], 'readiness': result['readiness'], 'api_statuses': result['api_statuses'],
        'error_count': len(result['projection_errors']), 'projection_errors': result['projection_errors'][:2]}, default=str))


if __name__ == '__main__':
    main()
