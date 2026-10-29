"""Preview existing blank sections eligible for the Capstone continuation rule.

Run: backend/venv/Scripts/python.exe execution/audit_capstone_section_progression.py
PostgreSQL enforces read-only access by default. --repair-current previews the
exact stale-label correction. Applying requires a reviewed revision, exact
counts, administrator identity, backup, and DEFENSYS_ALLOW_DEV_DB=1 on dev DB.
"""
import json
import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT / 'backend' / 'modules'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def inspect():
    from academic_period_management.services import active_semester
    from user_management.academic_records.models import StudentAcademicRecord
    from student_teams.continuation_sections import section_decisions
    term = active_semester()
    if not term:
        return {'mode': 'read_only', 'error': 'No active semester.'}
    records = list(StudentAcademicRecord.objects.filter(semester=term).select_related('student'))
    decisions = section_decisions(term, {r.student_id: r.year_level for r in records})
    candidates, review = [], []
    for record in records:
        if record.section.strip():
            continue
        decision = decisions[record.student_id]
        entry = {'record_id': record.pk, 'id_number': record.student.username,
            'year_level': record.year_level, 'previous_section': record.section, **decision}
        if decision['section'] and decision['source'] in ('inferred', 'admin'):
            candidates.append(entry)
        else:
            review.append(entry)
    return {'mode': 'database_enforced_read_only', 'automatic_repairs': False,
        'semester_id': term.pk, 'period': term.display_name,
        'candidate_count': len(candidates), 'unresolved_count': len(review),
        'candidates': candidates, 'unresolved': review,
        'next_step': 'Re-import enrollment for verified continuing students, or review official section assignments. '
            'Unverified teams and PIT enrollment receive no inferred continuation.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repair-current', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--semester-id', type=int)
    parser.add_argument('--actor-id', type=int)
    parser.add_argument('--revision', default='')
    parser.add_argument('--expect-teams', type=int)
    parser.add_argument('--expect-enrollments', type=int)
    parser.add_argument('--backup', type=Path)
    args = parser.parse_args()
    if args.apply and (not args.repair_current or not args.backup):
        parser.error('--apply requires --repair-current and --backup.')
    if args.backup and not args.backup.resolve().is_relative_to((ROOT / '.tmp').resolve()):
        parser.error('The correction backup must be inside .tmp.')
    import django
    django.setup()
    from django.db import connection, transaction
    if connection.vendor != 'postgresql':
        raise RuntimeError('PostgreSQL read-only transaction enforcement is required.')
    with transaction.atomic():
        if not args.apply:
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
        if args.repair_current:
            from academic_period_management.services import active_semester
            from django.contrib.auth import get_user_model
            from student_teams.section_progression_repair import correct_current_sections
            term_id = args.semester_id or active_semester().pk
            actor = get_user_model().objects.get(pk=args.actor_id) if args.actor_id else None
            result = correct_current_sections(semester_id=term_id, actor=actor, apply=args.apply,
                backup_path=args.backup, revision=args.revision, expected_teams=args.expect_teams,
                expected_enrollments=args.expect_enrollments)
        else:
            result = inspect()
    output = ROOT / '.tmp' / ('capstone-section-correction-result.json' if args.apply else
        'capstone-section-correction-preview.json' if args.repair_current else 'capstone-section-progression-review.json')
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('mode', 'candidate_count', 'unresolved_count',
        'team_count', 'enrollment_count', 'revision', 'applied', 'blockers', 'assignments')
        if key in result} | {'output': str(output)}))


if __name__ == '__main__':
    main()
