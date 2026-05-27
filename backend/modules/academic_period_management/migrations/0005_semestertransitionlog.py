from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('academic_period_management', '0004_semester_capstone_team_window'),
    ]

    operations = [
        migrations.CreateModel(
            name='SemesterTransitionLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('forced', models.BooleanField(default=False)),
                ('reason', models.TextField(blank=True)),
                ('impact_snapshot', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('changed_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='semester_transition_logs', to=settings.AUTH_USER_MODEL)),
                ('from_semester', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='transition_logs_from', to='academic_period_management.semester')),
                ('to_semester', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='transition_logs_to', to='academic_period_management.semester')),
            ],
            options={
                'ordering': ['-created_at', '-id'],
            },
        ),
    ]
