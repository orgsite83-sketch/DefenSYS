"""Profile faculty/cohort API reads against existing data without database writes.

Run with backend/venv/Scripts/python.exe from the repository root. Each request
runs inside a PostgreSQL READ ONLY transaction; no tokens or credentials are
created, and no roster names, response bodies, or SQL are printed. Timings are
in-process server timings, not browser or network measurements.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from time import perf_counter


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
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction
    from django.test.utils import CaptureQueriesContext
    from django.urls import resolve
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
        if user is None:
            continue
        found = True
        for path in READS:
            try:
                with transaction.atomic():
                    with connection.cursor() as cursor:
                        cursor.execute('SET TRANSACTION READ ONLY')
                    request = factory.get(path)
                    force_authenticate(request, user=user)
                    match = resolve(path)
                    with CaptureQueriesContext(connection) as queries:
                        started = perf_counter()
                        response = match.func(request, *match.args, **match.kwargs)
                        response.render()
                        elapsed = perf_counter() - started
                    result = dict(year=year, path=path, status=response.status_code,
                                  queries=len(queries), milliseconds=round(elapsed * 1000, 1),
                                  response_bytes=len(response.content))
            except Exception as error:
                # Avoid printing exception text that could contain SQL/data.
                result = dict(year=year, path=path, error=type(error).__name__)
            print(json.dumps(result), flush=True)
    if not found:
        raise SystemExit('No matching active PIT Lead was found; no accounts were changed.')


if __name__ == '__main__':
    main()
