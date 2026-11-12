"""Inspect existing curriculum classifications in a PostgreSQL READ ONLY transaction.

Run with backend/venv/Scripts/python.exe. No tokens, accounts, grades or stored
classifications are changed. Optional evidence stays in local diagnostic output.
"""
import argparse
from collections import Counter
import hashlib
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
    parser.add_argument('--project-status', choices=('all', 'completed'), default='all')
    parser.add_argument('--review-output', type=Path, help='Export unlabelled sources for independent review; never overwrites a file.')
    parser.add_argument('--training-families', type=int, default=0, help='Families assigned to training; default 0 exports all projects as a test set for a frozen, independently trained model.')
    args = parser.parse_args()
    if args.review_output and (args.scope == 'all' or (args.scope == 'pit' and not args.year_level)):
        parser.error('Review export requires one explicit scope and PIT year level when applicable.')
    if args.training_families < 0:
        parser.error('--training-families cannot be negative.')
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
                    'project_status': args.project_status,
                })
                data = explorer.payload()
                rows = data.get('projects', [])
                result = dict(scope=scope, year_level=level, projects=len(rows),
                              categories=dict(Counter(p['category'] for p in rows)),
                              application_areas=dict(Counter(p.get('application_area') for p in rows)),
                              application_area_reasons=dict(Counter(p.get('application_area_reason_code') for p in rows)),
                              computing_focus_reasons=dict(Counter(p.get('classification_reason_code') for p in rows)),
                              domains=dict(Counter(p['domain'] for p in rows)))
                if args.review_output:
                    # Hide model predictions from independent label review.
                    # All versions from a team stay in one project family.
                    families = sorted({str(row['team_id']) for row in rows}, key=lambda value:
                                      hashlib.sha256(('defensys-study-v1:' + value).encode()).hexdigest())
                    if len(families) <= args.training_families:
                        raise SystemExit('Not enough project families for the requested training split and a held-out test set. No export written.')
                    training = set(families[:args.training_families])
                    review = []
                    for row in rows:
                        project = next(p for p in explorer.projects.values() if p['key'] == row['id'])
                        project = {**project, 'title': row['project_title']}
                        docs = explorer._documents(project)
                        related = explorer._related_documents(project, [d for d in docs if d['readable']])
                        texts = list(dict.fromkeys(d['_raw_text'] for d in related))
                        review.append(dict(project_id=row['id'], project_family_id=str(row['team_id']),
                            project_title=row['project_title'], academic_year=args.academic_year,
                            text='\n\n'.join(texts), label='', reviewed=False,
                            split='train' if str(row['team_id']) in training else 'test',
                            extraction_status='readable' if texts else 'missing_or_unreadable',
                            documents=[dict(id=d['id'], label=d['label'], display_name=d['display_name'],
                                            uploaded_at=d['uploaded_at'], file_name=d['file_name'], text=d['_raw_text'])
                                       for d in related],
                            sources=[dict(id=d['id'], label=d['display_name'], file_name=d['file_name'],
                                          extracted_characters=len(d['_raw_text'])) for d in docs]))
                    args.review_output.parent.mkdir(parents=True, exist_ok=True)
                    with args.review_output.open('x', encoding='utf-8') as output:
                        json.dump(review, output, indent=2, ensure_ascii=False)
                    result['review_export'] = dict(path=str(args.review_output), projects=len(review),
                        splits=dict(Counter(r['split'] for r in review)),
                        note='Unreviewed split proposal. Check theme representation during independent labelling, then freeze before training or examining test predictions.')
                if args.include_evidence:
                    details = []
                    for row in rows:
                        project = next(p for p in explorer.projects.values() if p['key'] == row['id'])
                        category = explorer._category(project)
                        document = next((d for d in explorer._documents(project)
                                         if d['id'] == category.get('document_id')), None)
                        details.append(dict(title=row['project_title'], category=row['category'],
                                            application_area=category.get('application_area'),
                                            application_area_reason=category.get('application_area_reason'),
                                            application_area_reason_code=category.get('application_area_reason_code'),
                                            application_area_candidates=category.get('application_area_candidates'),
                                            application_area_candidate_evidence=category.get('application_area_candidate_evidence'),
                                            model_version=category.get('model_version'),
                                            feature_version=category.get('feature_version'),
                                            computing_focus_candidates=category.get('candidates'),
                                            sources=[dict(id=d['id'], label=d['display_name'], readable=d['readable'],
                                                          extracted_characters=len(d['_raw_text']))
                                                     for d in explorer._documents(project)],
                                            domain=row['domain'], reason=category['reason'],
                                            method=category.get('decision_method'),
                                            domain_evidence=category.get('domain_evidence'),
                                            text=document['_raw_text'] if document else ''))
                    result['details'] = details
                print(json.dumps(result, ensure_ascii=True), flush=True)


if __name__ == '__main__':
    main()
