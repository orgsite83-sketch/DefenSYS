"""Inspect existing curriculum classifications in a PostgreSQL READ ONLY transaction.

Run with backend/venv/Scripts/python.exe. No tokens, accounts, grades or stored
classifications are changed. Optional evidence stays in local diagnostic output.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--academic-year', default='2026-2027')
    parser.add_argument('--scope', choices=('capstone', 'pit', 'all'), default='all')
    parser.add_argument('--year-level', choices=('1', '2', '3'))
    parser.add_argument('--include-evidence', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction
    from curriculum_analytics.explorer import CurriculumExplorer

    if connection.vendor != 'postgresql':
        raise SystemExit('This audit requires PostgreSQL READ ONLY transactions.')
    scopes = ('capstone', 'pit') if args.scope == 'all' else (args.scope,)
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        admin = get_user_model().objects.filter(role='admin', is_active=True).first()
        if admin is None:
            raise SystemExit('No existing administrator found. No accounts were changed.')
        for scope in scopes:
            levels = (args.year_level,) if args.year_level else ('1', '2', '3')
            for level in levels if scope == 'pit' else ('',):
                explorer = CurriculumExplorer(admin, {
                    'view': 'projects', 'scope': scope, 'year_level': level,
                    'academic_year': args.academic_year,
                    'year_from': args.academic_year, 'year_to': args.academic_year,
                })
                data = explorer.payload()
                rows = data.get('projects', [])
                result = dict(scope=scope, year_level=level, projects=len(rows),
                              categories=dict(Counter(p['category'] for p in rows)),
                              application_areas=dict(Counter(p.get('application_area') for p in rows)),
                              domains=dict(Counter(p['domain'] for p in rows)))
                if args.include_evidence:
                    details = []
                    for row in rows:
                        project = next(p for p in explorer.projects.values() if p['key'] == row['id'])
                        category = explorer._category(project)
                        document = next((d for d in explorer._documents(project)
                                         if d['id'] == category.get('document_id')), None)
                        details.append(dict(title=row['project_title'], category=row['category'],
                                            application_area=category.get('application_area'),
                                            domain=row['domain'], reason=category['reason'],
                                            method=category.get('decision_method'),
                                            domain_evidence=category.get('domain_evidence'),
                                            text=document['_raw_text'] if document else ''))
                    result['details'] = details
                print(json.dumps(result, ensure_ascii=True), flush=True)


if __name__ == '__main__':
    main()
