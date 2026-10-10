"""Preview or remove reviewed peer-only grade rows with an exclusive recovery copy.

Preview is read-only. Applying to the development DB requires the db_guard escape
hatch, the exact database name, explicit grade IDs, and the expected team count.
"""
import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / 'backend'))


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--semester-id', type=int, required=True)
    parser.add_argument('--stage', required=True)
    parser.add_argument('--expected-team-count', type=int, required=True)
    parser.add_argument('--grade-ids', type=int, nargs='+')
    parser.add_argument('--database-name')
    parser.add_argument('--backup-path')
    parser.add_argument('--reason')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    django.setup()
    from django.db import connection, transaction
    from defensys_backend.db_guard import assert_safe_for_orm_writes, current_database_name
    from grading.grades.peer_cleanup import preview_cleanup, remove_unscheduled_peer_grades
    if args.apply:
        assert_safe_for_orm_writes()
        if not args.database_name or args.database_name != current_database_name():
            parser.error('--database-name must match the configured database exactly.')
        if not args.grade_ids or not args.backup_path or not args.reason:
            parser.error('Applying requires --grade-ids, --backup-path, and --reason.')
        backup = Path(args.backup_path).resolve()
        if not backup.is_relative_to((REPO_ROOT / '.tmp').resolve()):
            parser.error('The backup must be inside the repository .tmp directory.')
        preview = preview_cleanup(args.semester_id, args.stage)
        if len(preview) != args.expected_team_count or len(set(args.grade_ids)) != args.expected_team_count:
            parser.error('The expected team count does not match the reviewed candidates.')
        result = remove_unscheduled_peer_grades(semester_id=args.semester_id, stage_label=args.stage,
            grade_ids=args.grade_ids, backup_path=backup, reason=args.reason)
        print(json.dumps(result, indent=2))
    else:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
            preview = preview_cleanup(args.semester_id, args.stage)
            if len(preview) != args.expected_team_count:
                parser.error('The expected team count does not match the preview.')
            print(json.dumps({'database': current_database_name(), 'candidates': preview}, indent=2))


if __name__ == '__main__':
    run()
