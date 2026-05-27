import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('defense', '0009_stagegradingconfig_rubrics'),
        ('grading', '0005_explicit_stage_identity'),
    ]

    operations = [
        migrations.CreateModel(
            name='PanelistGradeSubmission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('guest_code_id', models.CharField(blank=True, max_length=64, null=True)),
                ('guest_code', models.CharField(blank=True, max_length=64)),
                ('guest_name', models.CharField(blank=True, max_length=160)),
                ('remarks', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('panelist', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='panelist_grade_submissions', to=settings.AUTH_USER_MODEL)),
                ('schedule', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='panelist_grade_submissions', to='defense.defenseschedule')),
                ('team_grade', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='panelist_submissions', to='grading.teamgrade')),
            ],
            options={
                'db_table': 'grade_center_panelistgradesubmission',
                'ordering': ['-updated_at', '-id'],
            },
        ),
        migrations.CreateModel(
            name='PanelistCriterionScore',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('criterion_name_snapshot', models.CharField(max_length=160)),
                ('score', models.DecimalField(decimal_places=2, max_digits=7)),
                ('max_score_snapshot', models.DecimalField(decimal_places=2, max_digits=7)),
                ('display_order', models.PositiveSmallIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('criterion', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='panelist_scores', to='grading.rubriccriterion')),
                ('submission', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='criterion_scores', to='grading.panelistgradesubmission')),
            ],
            options={
                'db_table': 'grade_center_panelistcriterionscore',
                'ordering': ['display_order', 'id'],
            },
        ),
        migrations.AddConstraint(
            model_name='panelistgradesubmission',
            constraint=models.UniqueConstraint(condition=models.Q(('panelist__isnull', False)), fields=('team_grade', 'schedule', 'panelist'), name='unique_panel_submission_per_panelist'),
        ),
        migrations.AddConstraint(
            model_name='panelistgradesubmission',
            constraint=models.UniqueConstraint(condition=models.Q(('guest_code_id__isnull', False)), fields=('team_grade', 'schedule', 'guest_code_id'), name='unique_panel_submission_per_guest'),
        ),
        migrations.AddIndex(
            model_name='panelistgradesubmission',
            index=models.Index(fields=['team_grade', 'schedule'], name='grade_cente_panel__ctx_idx'),
        ),
        migrations.AddIndex(
            model_name='panelistgradesubmission',
            index=models.Index(fields=['guest_code_id'], name='grade_cente_guest_c_idx'),
        ),
        migrations.AddConstraint(
            model_name='panelistcriterionscore',
            constraint=models.UniqueConstraint(fields=('submission', 'criterion'), name='unique_panel_score_per_criterion'),
        ),
        migrations.AddIndex(
            model_name='panelistcriterionscore',
            index=models.Index(fields=['criterion'], name='grade_cente_crit_id_idx'),
        ),
    ]
