"""Inspect public library filters inside a PostgreSQL READ ONLY transaction.

Run with backend/venv/Scripts/python.exe. Reports existing publication coverage,
not measured classification accuracy. No files, approvals, credentials or stored
classifications are changed. JSON output belongs under .tmp/.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--academic-year')
    parser.add_argument('--scope', choices=('pit', 'capstone', 'all'), default='all')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.db import connection, transaction
    from repository.archive.services import all_visible_entries
    from repository.archive.public_taxonomy import public_facets, VERSION

    if connection.vendor != 'postgresql':
        raise SystemExit('This audit requires PostgreSQL READ ONLY transactions.')
    started = time.perf_counter()
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        entries = all_visible_entries()
        entries = [entry for entry in entries
                   if (not args.academic_year or entry.get('academic_year') == args.academic_year)
                   and (args.scope == 'all' or entry.get('type') == args.scope)]
        projects = {}
        for entry in entries:
            projects.setdefault(entry['project_key'], entry)
        rows = [{'title': entry['display_title'], 'year': entry['academic_year'],
                 'type': entry['type'], 'tags': entry['library_tags']}
                for entry in projects.values()]
        result = {'taxonomy_version': VERSION, 'projects': len(projects), 'outputs': len(entries),
                  'facets': public_facets(entries, {}),
                  'missing': dict(Counter(group for entry in projects.values()
                                          for group, tags in entry['library_tags'].items() if not tags)),
                  'details': rows, 'seconds': round(time.perf_counter() - started, 3)}
    if args.output:
        path = args.output.resolve()
        if not path.is_relative_to(root / '.tmp'):
            raise SystemExit('Diagnostic output must stay under the workspace .tmp directory.')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'details'}, ensure_ascii=True))


if __name__ == '__main__':
    main()
