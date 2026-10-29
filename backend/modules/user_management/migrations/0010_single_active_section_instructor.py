from django.db import migrations, models
from django.db.models import Count


def require_resolved_duplicates(apps, schema_editor):
    assignment = apps.get_model('user_management', 'SectionInstructorAssignment')
    duplicates = list(assignment.objects.using(schema_editor.connection.alias).filter(is_active=True)
        .values('semester_id', 'year_level', 'section').annotate(count=Count('pk')).filter(count__gt=1))
    if duplicates:
        raise RuntimeError('Resolve duplicate active instructors through PIT Instructor assignments '
            f'before applying this migration. Retain the intended instructor and deactivate the others: {duplicates}')


class Migration(migrations.Migration):
    dependencies = [('user_management', '0009_guest_invitation_anchor')]
    operations = [
        migrations.RunPython(require_resolved_duplicates, migrations.RunPython.noop),
        migrations.AddConstraint(model_name='sectioninstructorassignment', constraint=models.UniqueConstraint(
            fields=('semester', 'year_level', 'section'), condition=models.Q(is_active=True),
            name='unique_active_section_instructor')),
    ]
