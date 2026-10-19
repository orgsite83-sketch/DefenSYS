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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--year', choices=('1st Year', '2nd Year', '3rd Year'))
    parser.add_argument('--curriculum', action='store_true', help='Measure curriculum explorer reads instead.')
    parser.add_argument('--profile', action='store_true', help='Save function timings under .tmp/.')
    parser.add_argument('--initial', action='store_true', help='Use the single-request curriculum startup.')
    parser.add_argument('--workspace', action='store_true', help='Measure progressive overview and project views.')
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction
    from django.test.utils import CaptureQueriesContext
    from django.urls import resolve
    from academic_period_management.models import Semester
    from rest_framework.test import APIRequestFactory, force_authenticate

    if connection.vendor != 'postgresql':
        raise SystemExit('This profiler requires PostgreSQL READ ONLY transactions.')
    factory = APIRequestFactory()
    years = [args.year] if args.year else ['1st Year', '2nd Year', '3rd Year']
    found = False
    for year in years:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
            user = get_user_model().objects.filter(
                is_active=True, role='faculty', is_pit_lead=True, pit_lead_year=year,
            ).order_by('pk').first()
            active_year = Semester.objects.filter(is_active=True).values_list('school_year__label', flat=True).first()
        if user is None:
            continue
        found = True
        reads = READS
        if args.curriculum:
            base = '/api/curriculum-analytics/explorer/'
            reads = [base + '?initial=true' if args.initial else base]
            if active_year:
                reads.append(base + '?' + urlencode({'academic_year': active_year}))
            if args.workspace:
                reads = [base + '?view=overview', base + '?view=projects', base + '?view=project_output']
        for index, path in enumerate(reads):
            try:
                with transaction.atomic():
                    with connection.cursor() as cursor:
                        cursor.execute('SET TRANSACTION READ ONLY')
                    request = factory.get(path)
                    force_authenticate(request, user=user)
                    match = resolve(urlsplit(path).path)
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
                    if profiler:
                        output = ROOT / '.tmp' / f'faculty-read-{year[0]}-{index}.prof'
                        output.parent.mkdir(parents=True, exist_ok=True)
                        profiler.dump_stats(output)
            except Exception as error:
                # Avoid printing exception text that could contain SQL/data.
                result = dict(year=year, path=path, error=type(error).__name__)
            print(json.dumps(result), flush=True)
    if not found:
        raise SystemExit('No matching active PIT Lead was found; no accounts were changed.')


if __name__ == '__main__':
    main()
