"""Map legacy approvals after schema changes commit; never renew authorization."""
from django.db import migrations


def map_legacy_batches(apps, schema_editor):
    Exception = apps.get_model('student_teams', 'AdviserCapacityException')
    Transition = apps.get_model('academic_period_management', 'SemesterTransitionLog')
    alias = schema_editor.connection.alias
    approvals = Exception.objects.using(alias)
    # 0027 was originally shipped with a backfill. Already mapped approvals,
    # including later revocations/retirements, must remain completely untouched.
    occupied = set(approvals.filter(intake_semester_id__isnull=False).values_list(
        'adviser_id', 'intake_semester_id'))
    unresolved = approvals.filter(intake_semester_id__isnull=True)
    unresolved.filter(ended_at__isnull=False, end_kind='').update(end_kind='legacy_ended')
    candidates = {}
    for row in unresolved.select_related('semester__school_year').order_by('pk'):
        term = row.semester
        intake_id = term.pk if term.label == '2nd Semester' else None
        if term.label == '1st Semester':
            log = Transition.objects.using(alias).filter(to_semester_id=term.pk,
                operation='activation').select_related('from_semester__school_year').order_by('-pk').first()
            source = log.from_semester if log else None
            snapshot = log.impact_snapshot if log else {}
            if source and source.label == '2nd Semester' and snapshot.get('applied_team_ids'):
                try:
                    start, end = map(int, source.school_year.label.split('-'))
                    consecutive = term.school_year.label == f'{start + 1}-{end + 1}'
                except ValueError:
                    consecutive = False
                if consecutive and snapshot.get('capstone_review', {}).get('kind') == 'continue':
                    intake_id = source.pk
        if intake_id:
            candidates.setdefault((row.adviser_id, intake_id), []).append(row.pk)
    # Keep conflicts unresolved, including conflicts with already mapped rows.
    for key, ids in candidates.items():
        if len(ids) == 1 and key not in occupied:
            unresolved.filter(pk=ids[0]).update(intake_semester_id=key[1])


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0027_adviser_capacity_batch')]
    operations = [migrations.RunPython(map_legacy_batches, migrations.RunPython.noop)]
