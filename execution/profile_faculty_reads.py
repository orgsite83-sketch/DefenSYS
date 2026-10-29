"""Profile faculty/cohort API reads against existing data without database writes.

Run with backend/venv/Scripts/python.exe from the repository root. Each request
runs inside a PostgreSQL READ ONLY transaction; no tokens or credentials are
created, and no roster names, response bodies, or SQL are printed. Timings are
in-process server timings, not browser or network measurements.
"""
from __future__ import annotations

import argparse
import cProfile
import json
import os
from pathlib import Path
import sys
from time import perf_counter
from urllib.parse import urlencode, urlsplit


ROOT = Path(__file__).resolve().parents[1]
READS = (
    '/api/dashboards/faculty/',
    '/api/dashboards/pit-lead/cohort/',
    '/api/users/pit-instructors/',
    '/api/academic-periods/',
    '/api/users/academic-records/',
    '/api/users/',
)


def profile_deliverable_responses(args):
    """Measure post-action serialization only; never submit a live review."""
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction, reset_queries
    from django.db.models import Count
    from django.test import override_settings
    from django.test.utils import CaptureQueriesContext
    from rest_framework.request import Request
    from rest_framework.renderers import JSONRenderer
    from rest_framework.test import APIRequestFactory
    from student_teams.models import StudentTeam
    from repository.deliverables.services import current_stage_for_team
    from repository.deliverables.views import deliverables_action_payload, get_allowed_team

    if connection.vendor != 'postgresql':
        raise SystemExit('This profiler requires PostgreSQL READ ONLY transactions.')
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        assignment = StudentTeam.objects.filter(semester__is_active=True,
            adviser__is_active=True, adviser__is_adviser=True, adviser__role='faculty',
            level__icontains='Capstone').values('adviser_id').annotate(total=Count('pk')).order_by('-total', 'adviser_id').first()
        if not assignment:
            raise SystemExit('No matching active adviser was found; no accounts were changed.')
        user = get_user_model().objects.get(pk=assignment['adviser_id'])
        teams = StudentTeam.objects.filter(semester__is_active=True, adviser=user,
            level__icontains='Capstone').order_by('pk')[:3]
        samples = [(team.pk, current_stage_for_team(team)) for team in teams]
    factory = APIRequestFactory()
    for index, (team_id, label) in enumerate(samples):
        for mode in (args.response_mode,):
            with transaction.atomic(), override_settings(READ_PROJECTION_CACHE_ENABLED=not args.uncached):
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
                params = {'scope': 'capstone', 'workspace': 'adviser', 'stage_label': label or ''}
                if mode == 'team':
                    params['response_mode'] = 'team'
                request = Request(factory.get('/api/repository/deliverables/review/', params))
                request.user = user
                profiler = cProfile.Profile() if args.profile else None
                # Django bounds its query log. Clear prior samples so a large
                # uncached response cannot truncate later measurements.
                reset_queries()
                with CaptureQueriesContext(connection) as queries:
                    started = perf_counter()
                    if profiler:
                        profiler.enable()
                    team = get_allowed_team(request, team_id)
                    data = deliverables_action_payload(request, team, label)
                    content = JSONRenderer().render(data)
                    if profiler:
                        profiler.disable()
                    elapsed = perf_counter() - started
                print(json.dumps(dict(measurement='response_only', sample=index,
                    response_mode=mode, read_reuse=not args.uncached, queries=len(queries),
                    milliseconds=round(elapsed * 1000, 1), response_bytes=len(content))), flush=True)
                if profiler:
                    output = ROOT / '.tmp' / f'deliverable-response-{index}-{mode}-{args.uncached}.prof'
                    output.parent.mkdir(parents=True, exist_ok=True)
                    profiler.dump_stats(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--year', choices=('1st Year', '2nd Year', '3rd Year'))
    parser.add_argument('--curriculum', action='store_true', help='Measure curriculum explorer reads instead.')
    parser.add_argument('--profile', action='store_true', help='Save function timings under .tmp/.')
    parser.add_argument('--initial', action='store_true', help='Use the single-request curriculum startup.')
    parser.add_argument('--workspace', action='store_true', help='Measure progressive overview and project views.')
    parser.add_argument('--archive', action='store_true', help='Measure each level of the project archive browser.')
    parser.add_argument('--admin', action='store_true', help='Profile an existing administrator instead of PIT Leads.')
    parser.add_argument('--schedule-import', action='store_true', help='Compare full schedule reads with import conflict checks.')
    parser.add_argument('--stage-setup', action='store_true', help='Measure the stage directory, detail and Capstone rubric reads.')
    parser.add_argument('--grade-completion', action='store_true', help='Measure completion previews for existing graded groups; never mark a group complete.')
    parser.add_argument('--deliverable-responses', action='store_true', help='Measure adviser action responses without reviewing or changing any file.')
    parser.add_argument('--uncached', action='store_true', help='Disable request-local read reuse for the deliverable response benchmark.')
    parser.add_argument('--response-mode', choices=('team', 'full'), default='team',
        help='Deliverable response to measure; current clients request one team.')
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    if args.deliverable_responses:
        profile_deliverable_responses(args)
        return
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction, reset_queries
    from django.test.utils import CaptureQueriesContext
    from django.urls import resolve
    from academic_period_management.models import Semester
    from rest_framework.test import APIRequestFactory, force_authenticate

    if connection.vendor != 'postgresql':
        raise SystemExit('This profiler requires PostgreSQL READ ONLY transactions.')
    factory = APIRequestFactory()
    years = ['admin'] if args.admin else ([args.year] if args.year else ['1st Year', '2nd Year', '3rd Year'])
    found = False
    for year in years:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
            user_filter = {'role': 'admin'} if args.admin else {
                'role': 'faculty', 'is_pit_lead': True, 'pit_lead_year': year,
            }
            user = get_user_model().objects.filter(is_active=True, **user_filter).order_by('pk').first()
            active_year = Semester.objects.filter(is_active=True).values_list('school_year__label', flat=True).first()
            if args.stage_setup:
                from defense.stages.models import DefenseStage
                stage_id = DefenseStage.objects.order_by('display_order', 'pk').values_list('pk', flat=True).first()
        if user is None:
            continue
        found = True
        reads = READS
        if args.schedule_import:
            reads = ['/api/defense/schedules/?status=scheduled',
                     '/api/defense/schedules/?view=import-conflicts']
        if args.curriculum:
            base = '/api/curriculum-analytics/explorer/'
            reads = [base + '?initial=true' if args.initial else base]
            if active_year:
                reads.append(base + '?' + urlencode({'academic_year': active_year}))
            if args.workspace:
                reads = [base + '?view=overview', base + '?view=projects', base + '?view=project_output']
        if args.archive:
            reads = ['/api/repository/audit/?open_current_semester=1']
        if args.stage_setup:
            reads = ['/api/defense/stages/']
            if stage_id:
                reads.append(f'/api/defense/stages/{stage_id}/')
            reads.append('/api/grading/rubrics/?scope=capstone')
        if args.grade_completion:
            from grading.grades.models import TeamGrade
            with transaction.atomic():
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
                groups = TeamGrade.objects.filter(semester__is_active=True)
                if not args.admin:
                    groups = groups.filter(scope='pit', team__year_level=year)
                samples = list(groups.order_by('scope', 'stage_label').values_list(
                    'scope', 'stage_label').distinct())
            reads = ['/api/grading/grades/group-settings/?' + urlencode({
                'workspace': 'operations', 'scope': scope, 'stage_label': label,
            }) for scope, label in samples]
        for index, path in enumerate(reads):
            try:
                with transaction.atomic():
                    with connection.cursor() as cursor:
                        cursor.execute('SET TRANSACTION READ ONLY')
                    request = factory.get(path)
                    force_authenticate(request, user=user)
                    match = resolve(urlsplit(path).path)
                    reset_queries()
                    with CaptureQueriesContext(connection) as queries:
                        profiler = cProfile.Profile() if args.profile else None
                        started = perf_counter()
                        if profiler:
                            profiler.enable()
                        response = match.func(request, *match.args, **match.kwargs)
                        response.render()
                        if profiler:
                            profiler.disable()
                        elapsed = perf_counter() - started
                    result = dict(year=year, path=path, status=response.status_code,
                                  queries=len(queries), milliseconds=round(elapsed * 1000, 1),
                                  response_bytes=len(response.content))
                    if args.grade_completion and response.status_code == 200:
                        result.update(team_count=response.data['grading_total_team_count'],
                            can_complete=response.data['can_complete'],
                            is_officially_complete=response.data['is_officially_complete'],
                            ready_team_count=response.data['completion_ready_team_count'],
                            incomplete_team_count=len(response.data['incomplete_teams']),
                            has_completion_token=bool(response.data['completion_token']))
                    if args.archive and response.status_code == 200:
                        folders = response.data.get('folder_browser', {}).get('folders', [])
                        if folders and index < 5:
                            reads.append('/api/repository/audit/?' + urlencode({'folder_key': folders[0]['key']}))
                    if profiler:
                        output = ROOT / '.tmp' / f'faculty-read-{year[0]}-{index}.prof'
                        output.parent.mkdir(parents=True, exist_ok=True)
                        profiler.dump_stats(output)
            except Exception as error:
                # Avoid printing exception text that could contain SQL/data.
                result = dict(year=year, path=path, error=type(error).__name__)
            print(json.dumps(result), flush=True)
    if not found:
        role_label = 'administrator' if args.admin else 'PIT Lead'
        raise SystemExit(f'No matching active {role_label} was found; no accounts were changed.')


if __name__ == '__main__':
    main()
