"""Profile curriculum explorer reads in a PostgreSQL READ ONLY transaction.

Uses an existing administrator and Django's request factory. Outputs timings,
query counts and response sizes, never manuscript contents or credentials.
Run with backend/venv/Scripts/python.exe from the repository root.
"""
import argparse
import json
import os
from pathlib import Path
import sys
from time import perf_counter


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scope', choices=('capstone', 'pit'), default='capstone')
    parser.add_argument('--year-level', choices=('1', '2', '3'), default='1')
    parser.add_argument('--academic-year', default='')
    parser.add_argument('--output', default='')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = Path(args.output).resolve() if args.output else None
    if destination and not destination.is_relative_to((root / '.tmp').resolve()):
        raise SystemExit('--output must be inside the workspace .tmp directory.')
    sys.path.insert(0, str(root / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction
    from rest_framework.test import APIRequestFactory, force_authenticate
    from curriculum_analytics.views import CurriculumExplorerView

    if connection.vendor != 'postgresql':
        raise SystemExit('PostgreSQL READ ONLY transactions are required.')
    factory = APIRequestFactory()
    results = []
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        admin = get_user_model().objects.filter(role='admin', is_active=True).first()
        if admin is None:
            raise SystemExit('No existing administrator is available. No accounts were created.')

        def probe(view, phase, **extra):
            queries = 0

            def count(execute, sql, params, many, context):
                nonlocal queries
                queries += 1
                return execute(sql, params, many, context)

            params = {'scope': args.scope, 'year_level': args.year_level, 'view': view, **extra}
            request = factory.get('/api/curriculum-analytics/explorer/', params)
            force_authenticate(request, admin)
            started = perf_counter()
            with connection.execute_wrapper(count):
                response = CurriculumExplorerView.as_view()(request)
                response.render()
            results.append({'view': view, 'phase': phase, 'status': response.status_code,
                'milliseconds': round((perf_counter() - started) * 1000, 2),
                'queries': queries, 'bytes': len(response.content)})
            if response.status_code != 200:
                raise RuntimeError(f'{view} returned HTTP {response.status_code}.')
            return response.data

        overview = probe('overview', 'cold')
        year = args.academic_year or next(reversed(overview['academic_years']), '')
        probe('overview', 'warm')
        if year:
            probe('year', 'cold', academic_year=year, workspace='true')
            probe('year', 'warm', academic_year=year, workspace='true')
            probe('projects', 'cold', academic_year=year, project_status='all')
            probe('projects', 'warm', academic_year=year, project_status='all')
    report = {'scope': args.scope, 'year_level': args.year_level if args.scope == 'pit' else None,
              'academic_year': year, 'read_only': True, 'results': results}
    encoded = json.dumps(report, indent=2)
    if destination:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(encoded, encoding='utf-8')
    print(encoded)


if __name__ == '__main__':
    main()
