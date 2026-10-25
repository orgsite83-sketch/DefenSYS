"""Read-only calendar audit; optional exact, backed-up demo correction.

Apply requires explicit parameters, --apply, --actor-id, and the repository's
DEFENSYS_ALLOW_DEV_DB=1 opt-in when the selected database is not a test database.
"""
import argparse
from datetime import date
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--semester-id', type=int)
    parser.add_argument('--rebase-to-semester-id', type=int)
    parser.add_argument('--year-label')
    parser.add_argument('--expect-teams', type=int)
    parser.add_argument('--expect-enrollments', type=int)
    parser.add_argument('--expect-capstone-teams', type=int)
    parser.add_argument('--preview-revision', default='')
    parser.add_argument('--starts-on', type=date.fromisoformat)
    parser.add_argument('--ends-on', type=date.fromisoformat)
    parser.add_argument('--from-date', type=date.fromisoformat)
    parser.add_argument('--to-date', type=date.fromisoformat)
    parser.add_argument('--expect-count', type=int)
    parser.add_argument('--actor-id', type=int)
    parser.add_argument('--reason', default='Administrator-authorized correction of sample calendar data')
    parser.add_argument('--backup', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    import django
    django.setup()
    from django.db import connection, transaction
    from django.core.serializers.json import DjangoJSONEncoder
    from academic_period_management.models import Semester
    from academic_period_management.calendar import calendar_schedule_issues
    with transaction.atomic():
        if not args.apply:
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
        if args.rebase_to_semester_id is not None:
            required = [args.semester_id, args.year_label, args.expect_teams,
                        args.expect_enrollments, args.expect_capstone_teams]
            if any(value is None for value in required):
                parser.error('Rebase requires exact source/target IDs, year label and team/enrollment counts.')
            if any(value is not None for value in (args.starts_on, args.ends_on, args.from_date, args.to_date)):
                parser.error('A baseline rebase preserves dates; do not combine it with date correction.')
            if args.apply and (args.backup is None or args.actor_id is None or not args.preview_revision):
                parser.error('Apply requires --backup, --actor-id and --preview-revision.')
            if args.backup and not args.backup.resolve().is_relative_to((ROOT / '.tmp').resolve()):
                parser.error('The rebase recovery file must be inside .tmp.')
            from django.contrib.auth import get_user_model
            from academic_period_management.demo_rebase import rebase_demo_term
            actor = get_user_model().objects.get(pk=args.actor_id) if args.actor_id else None
            result = rebase_demo_term(source_id=args.semester_id, target_id=args.rebase_to_semester_id,
                expected_year=args.year_label, expected_teams=args.expect_teams,
                expected_enrollments=args.expect_enrollments, expected_capstone_teams=args.expect_capstone_teams,
                reason=args.reason, actor=actor, apply=args.apply, backup_path=args.backup,
                preview_revision=args.preview_revision)
        elif args.semester_id is not None:
            required = [args.starts_on, args.ends_on, args.from_date, args.to_date, args.expect_count]
            if any(value is None for value in required):
                parser.error('Correction preview requires start/end dates, source/target defense dates, and expected count.')
            if args.apply and (args.backup is None or args.actor_id is None):
                parser.error('--apply requires --backup and --actor-id.')
            from django.contrib.auth import get_user_model
            from academic_period_management.calendar_repair import repair_sample_calendar
            actor = get_user_model().objects.get(pk=args.actor_id) if args.actor_id else None
            result = repair_sample_calendar(semester_id=args.semester_id, starts_on=args.starts_on,
                ends_on=args.ends_on, source_date=args.from_date, target_date=args.to_date,
                expected_count=args.expect_count, actor=actor, reason=args.reason,
                backup_path=args.backup, apply=args.apply)
        else:
            if args.apply:
                parser.error('--apply requires an explicitly selected semester and correction dates.')
            result = {'database': connection.settings_dict['NAME'], 'periods': [
                {'id': term.pk, 'semester': term.display_name, 'active': term.is_active,
                 'starts_on': term.starts_on, 'ends_on': term.ends_on, **calendar_schedule_issues(term)}
                for term in Semester.objects.select_related('school_year').order_by('pk')]}
        print(json.dumps(result, cls=DjangoJSONEncoder, indent=2))


if __name__ == '__main__':
    main()
