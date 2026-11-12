"""Attach reliable legacy authorizations to their intake without renewing them."""
import django.db.models.deletion
from django.db import migrations, models


def map_legacy_batches(apps, schema_editor):
    Exception = apps.get_model('student_teams', 'AdviserCapacityException')
    Transition = apps.get_model('academic_period_management', 'SemesterTransitionLog')
    alias = schema_editor.connection.alias
    Exception.objects.using(alias).filter(ended_at__isnull=False).update(end_kind='legacy_ended')
    candidates = {}
    for row in Exception.objects.using(alias).select_related('semester__school_year').order_by('pk'):
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
    # Collisions remain unresolved instead of arbitrarily choosing an approval.
    for (_, intake_id), ids in candidates.items():
        if len(ids) == 1:
            Exception.objects.using(alias).filter(pk=ids[0]).update(intake_semester_id=intake_id)


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0026_adviser_capacity_exception')]
    operations = [
        migrations.AddField(model_name='advisercapacityexception', name='intake_semester',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT,
                related_name='intake_adviser_capacity_exceptions', to='academic_period_management.semester')),
        migrations.AddField(model_name='advisercapacityexception', name='end_kind',
            field=models.CharField(blank=True, default='', max_length=20, choices=[
                ('revoked', 'Revoked'), ('retired', 'Cycle ended'), ('legacy_ended', 'Previously ended')])),
        migrations.RunPython(map_legacy_batches, migrations.RunPython.noop),
        migrations.RemoveConstraint(model_name='advisercapacityexception', name='unique_adviser_capacity_term'),
        migrations.AddConstraint(model_name='advisercapacityexception',
            constraint=models.UniqueConstraint(fields=('adviser', 'intake_semester'), name='unique_adviser_capacity_intake')),
    ]
