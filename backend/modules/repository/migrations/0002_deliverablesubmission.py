import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('repository', '0001_vaultentry'),
        ('student_teams', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='DeliverableSubmission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('stage_label', models.CharField(max_length=80)),
                ('deliverable_id', models.CharField(max_length=20)),
                ('label', models.CharField(max_length=180)),
                ('deliverable_type', models.CharField(choices=[('pre', 'Pre-Defense'), ('vault', 'Vault')], max_length=20)),
                ('required', models.BooleanField(default=False)),
                ('file', models.FileField(blank=True, help_text='Actual uploaded file', null=True, upload_to='deliverables/%Y/%m/')),
                ('file_name', models.CharField(max_length=255)),
                ('file_size', models.CharField(blank=True, max_length=40)),
                ('extracted_text', models.TextField(blank=True, default='', help_text='Full text extracted from PDF for ML search')),
                ('topics', models.JSONField(blank=True, default=list, help_text='Auto-extracted keywords/topics from PDF content')),
                ('summary', models.TextField(blank=True, default='', help_text='Auto-generated summary of PDF content')),
                ('category', models.CharField(blank=True, default='', help_text='ML-predicted technology category', max_length=100)),
                ('category_confidence', models.FloatField(blank=True, help_text='Classification confidence score (0-100)', null=True)),
                ('uploaded_at', models.DateTimeField(auto_now=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='deliverable_submissions', to='student_teams.studentteam')),
                ('uploaded_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='uploaded_capstone_deliverables', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'capstone_deliverables_deliverablesubmission',
                'ordering': ['stage_label', 'deliverable_id'],
                'indexes': [
                    models.Index(fields=['stage_label', 'deliverable_type'], name='capstone_de_stage_l_d3e67b_idx'),
                    models.Index(fields=['deliverable_id'], name='capstone_de_deliver_e79675_idx'),
                ],
                'constraints': [
                    models.UniqueConstraint(
                        fields=('team', 'stage_label', 'deliverable_id'),
                        name='unique_deliverable_submission_per_team_stage',
                    ),
                ],
            },
        ),
    ]
