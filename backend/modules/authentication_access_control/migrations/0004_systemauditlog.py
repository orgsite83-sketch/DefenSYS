from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('authentication_access_control', '0003_user_repo_assistant_year'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='SystemAuditLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('action', models.CharField(max_length=80)),
                ('category', models.CharField(choices=[('academic_period', 'Academic Periods'), ('grade_center', 'Grade Center'), ('scheduling', 'Scheduling'), ('student_teams', 'Student Teams'), ('repository', 'Repository'), ('guest_access', 'Guest Access')], max_length=40)),
                ('target_type', models.CharField(max_length=80)),
                ('target_id', models.CharField(blank=True, max_length=80)),
                ('old_values', models.JSONField(blank=True, default=dict)),
                ('new_values', models.JSONField(blank=True, default=dict)),
                ('reason', models.TextField(blank=True)),
                ('review_status', models.CharField(choices=[('captured', 'Evidence Captured'), ('needs_review', 'Needs Review'), ('reviewed', 'Reviewed'), ('requires_reason', 'Requires Reason')], default='captured', max_length=30)),
                ('ip_address', models.GenericIPAddressField(blank=True, null=True)),
                ('user_agent', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('actor', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='system_audit_logs', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-created_at', '-id'],
            },
        ),
        migrations.AddIndex(
            model_name='systemauditlog',
            index=models.Index(fields=['created_at'], name='authenticat_created_36f139_idx'),
        ),
        migrations.AddIndex(
            model_name='systemauditlog',
            index=models.Index(fields=['category', 'created_at'], name='authenticat_categor_bfa156_idx'),
        ),
        migrations.AddIndex(
            model_name='systemauditlog',
            index=models.Index(fields=['actor', 'created_at'], name='authenticat_actor_i_e84a45_idx'),
        ),
        migrations.AddIndex(
            model_name='systemauditlog',
            index=models.Index(fields=['target_type', 'target_id', 'created_at'], name='authenticat_target__0f323c_idx'),
        ),
    ]
