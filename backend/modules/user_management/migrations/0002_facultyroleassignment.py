import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('user_management', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='FacultyRoleAssignment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('role_key', models.CharField(choices=[('panelist', 'Defense Panelist'), ('pit_lead', 'PIT Lead'), ('adviser', 'Project Adviser'), ('repo_assistant', 'Repository Assistant')], max_length=32)),
                ('role_detail', models.CharField(blank=True, max_length=100, null=True)),
                ('year_level', models.CharField(blank=True, max_length=50, null=True)),
                ('action', models.CharField(choices=[('assigned', 'Assigned'), ('revoked', 'Revoked')], max_length=16)),
                ('changed_at', models.DateTimeField(auto_now_add=True)),
                ('changed_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='faculty_role_changes_made', to=settings.AUTH_USER_MODEL)),
                ('semester', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='faculty_role_assignments', to='academic_period_management.semester')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='faculty_role_assignments', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-changed_at', '-id'],
            },
        ),
    ]
