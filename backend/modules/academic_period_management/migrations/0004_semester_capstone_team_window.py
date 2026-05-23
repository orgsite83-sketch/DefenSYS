from django.db import migrations, models


def apply_semester_defaults(apps, schema_editor):
    Semester = apps.get_model('academic_period_management', 'Semester')
    for semester in Semester.objects.all():
        if semester.label == '2nd Semester':
            semester.capstone_team_creation_enabled = True
            semester.capstone_program_phase = 'capstone_1'
        else:
            semester.capstone_team_creation_enabled = False
            semester.capstone_program_phase = 'none'
        semester.save(
            update_fields=['capstone_team_creation_enabled', 'capstone_program_phase'],
        )


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0003_alter_semester_capstone_flags_help_text'),
    ]

    operations = [
        migrations.AddField(
            model_name='semester',
            name='capstone_team_creation_enabled',
            field=models.BooleanField(
                default=False,
                help_text='When on, admins can create or bulk-import new capstone teams (Capstone 1 intake).',
            ),
        ),
        migrations.AddField(
            model_name='semester',
            name='capstone_program_phase',
            field=models.CharField(
                choices=[
                    ('none', 'None'),
                    ('capstone_1', 'Capstone 1 intake'),
                    ('capstone_2', 'Capstone 2 continue'),
                ],
                default='none',
                help_text='Capstone 1 = new team intake; Capstone 2 = same teams bumped via rollover.',
                max_length=20,
            ),
        ),
        migrations.RunPython(apply_semester_defaults, migrations.RunPython.noop),
    ]
