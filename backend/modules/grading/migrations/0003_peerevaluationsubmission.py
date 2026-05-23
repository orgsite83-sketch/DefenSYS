from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('grading', '0002_grades'),
    ]

    operations = [
        migrations.CreateModel(
            name='PeerEvaluationSubmission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('total_score', models.DecimalField(decimal_places=2, max_digits=7)),
                ('max_score', models.DecimalField(decimal_places=2, max_digits=7)),
                ('breakdown', models.JSONField(blank=True, default=list)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'evaluatee',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='peer_evaluations_received',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'evaluator',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='peer_evaluations_given',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'team_grade',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='peer_evaluation_submissions',
                        to='grading.teamgrade',
                    ),
                ),
            ],
            options={
                'db_table': 'grade_center_peerevaluationsubmission',
                'ordering': ['-updated_at', '-id'],
            },
        ),
        migrations.AddConstraint(
            model_name='peerevaluationsubmission',
            constraint=models.UniqueConstraint(
                fields=('team_grade', 'evaluator', 'evaluatee'),
                name='unique_peer_submission_per_evaluator_evaluatee',
            ),
        ),
    ]
