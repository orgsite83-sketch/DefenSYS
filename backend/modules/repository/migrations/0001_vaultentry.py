import django.db.models.deletion
import django.utils.timezone
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('student_teams', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='VaultEntry',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('entry_type', models.CharField(choices=[('pit', 'PIT'), ('capstone', 'Capstone')], default='pit', max_length=20)),
                ('file', models.FileField(blank=True, help_text='Actual uploaded file', null=True, upload_to='vault_entries/%Y/%m/')),
                ('file_name', models.CharField(max_length=255)),
                ('file_size', models.CharField(blank=True, max_length=40)),
                ('extracted_text', models.TextField(blank=True, default='', help_text='Full text extracted from PDF for ML search')),
                ('topics', models.JSONField(blank=True, default=list, help_text='Auto-extracted keywords/topics from PDF content')),
                ('summary', models.TextField(blank=True, default='', help_text='Auto-generated summary of PDF content')),
                ('team_name', models.CharField(blank=True, max_length=120)),
                ('year_level', models.CharField(blank=True, max_length=20)),
                ('course_code', models.CharField(blank=True, max_length=30)),
                ('semester_label', models.CharField(blank=True, max_length=30)),
                ('academic_year', models.CharField(blank=True, max_length=9)),
                ('stage_label', models.CharField(blank=True, max_length=80)),
                ('status', models.CharField(choices=[('Pending AI Classification', 'Pending AI Classification'), ('Approved', 'Approved'), ('Needs Revision', 'Needs Revision')], default='Pending AI Classification', max_length=40)),
                ('uploaded_by_name', models.CharField(blank=True, max_length=150)),
                ('uploaded_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('team', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='vault_entries', to='student_teams.studentteam')),
                ('uploaded_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='uploaded_vault_entries', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'digital_vault_vaultentry',
                'ordering': ['-uploaded_at', 'file_name'],
                'constraints': [
                    models.UniqueConstraint(
                        fields=('entry_type', 'file_name', 'academic_year'),
                        name='unique_vault_entry_per_academic_year',
                    ),
                ],
            },
        ),
    ]
