import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('user_management', '0003_studentacademicrecord'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='studentacademicrecord',
            name='section',
            field=models.CharField(blank=True, default='', max_length=80),
        ),
        migrations.CreateModel(
            name='PitInstructorAssignment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('year_level', models.CharField(max_length=50)),
                ('section', models.CharField(max_length=80)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('assigned_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='pit_instructor_assignments_made', to=settings.AUTH_USER_MODEL)),
                ('faculty', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='pit_instructor_assignments', to=settings.AUTH_USER_MODEL)),
                ('semester', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='pit_instructor_assignments', to='academic_period_management.semester')),
            ],
            options={
                'ordering': ['year_level', 'section', 'faculty__last_name', 'faculty__first_name'],
            },
        ),
        migrations.AddIndex(
            model_name='pitinstructorassignment',
            index=models.Index(fields=['semester', 'year_level', 'section', 'is_active'], name='pit_instr_scope_idx'),
        ),
        migrations.AddConstraint(
            model_name='pitinstructorassignment',
            constraint=models.UniqueConstraint(fields=('faculty', 'semester', 'year_level', 'section'), name='unique_pit_instructor_assignment'),
        ),
    ]
