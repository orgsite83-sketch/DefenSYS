from django.db import migrations, models


def migrate_rubric_audit_logs(apps, schema_editor):
    SystemAuditLog = apps.get_model('authentication_access_control', 'SystemAuditLog')
    SystemAuditLog.objects.filter(action__startswith='rubric.').update(category='rubrics')


def rollback_rubric_audit_logs(apps, schema_editor):
    SystemAuditLog = apps.get_model('authentication_access_control', 'SystemAuditLog')
    SystemAuditLog.objects.filter(category='rubrics').update(category='grade_center')


class Migration(migrations.Migration):

    dependencies = [
        ('authentication_access_control', '0016_sync_audit_categories'),
    ]

    operations = [
        migrations.AlterField(
            model_name='systemauditlog',
            name='category',
            field=models.CharField(
                choices=[
                    ('academic_period', 'Academic Periods'),
                    ('rubrics', 'Rubrics'),
                    ('grade_center', 'Evaluation & Grades'),
                    ('scheduling', 'Scheduling'),
                    ('student_teams', 'Student Teams'),
                    ('repository', 'Repository'),
                    ('guest_access', 'Guest Access'),
                    ('user_management', 'User Management'),
                ],
                max_length=40,
            ),
        ),
        migrations.RunPython(migrate_rubric_audit_logs, rollback_rubric_audit_logs),
    ]
