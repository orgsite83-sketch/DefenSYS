"""Read-only inventory before adopting managed weekly-report requirements.

Run from the project root with backend/venv/Scripts/python.exe. Only existing
legacy columns are selected, so this also works before the new schema migration.
No reports, deadlines, acceptance records, or academic settings are changed.
"""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT / 'backend' / 'modules'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def main():
    import django
    django.setup()
    from django.db import connection, transaction
    from defense.stages.models import StageDeliverable
    from repository.deliverables.models import DeliverableSubmission
    from student_teams.weekly_progress.models import WeeklyProgressReport
    if connection.vendor != 'postgresql':
        raise RuntimeError('This audit requires PostgreSQL read-only transaction enforcement.')
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        reports = list(WeeklyProgressReport.objects.order_by('pk').values(
            'id', 'team_id', 'student_id', 'week_number', 'report_date', 'submitted_at', 'report_file'))
        definitions = list(StageDeliverable.objects.filter(deliverable_id='WPR').values(
            'id', 'defense_stage_id', 'label', 'required'))
        compilations = list(DeliverableSubmission.all_objects.filter(deliverable_id='WPR').values(
            'id', 'team_id', 'stage_label', 'file_name', 'status', 'uploaded_at'))
    output = ROOT / '.tmp' / 'weekly-report-adoption-audit.json'
    output.parent.mkdir(exist_ok=True)
    result = {'read_only': True, 'legacy_reports': reports, 'ordinary_wpr_requirements': definitions,
        'wpr_submissions': compilations,
        'adoption_policy': 'Preserve unbound historical records. Require explicit context mapping and fresh '
            'individual adviser reviews before any legacy record can satisfy a managed collection.'}
    output.write_text(json.dumps(result, indent=2, default=str), encoding='utf-8')
    print(json.dumps({'read_only': True, 'legacy_reports': len(reports),
        'ordinary_wpr_requirements': len(definitions), 'wpr_submissions': len(compilations), 'output': str(output)}))


if __name__ == '__main__':
    main()
