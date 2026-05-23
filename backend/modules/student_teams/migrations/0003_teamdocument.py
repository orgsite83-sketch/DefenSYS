import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('student_teams', '0002_team_adviser_assignment'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='TeamDocument',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('document_type', models.CharField(choices=[('proposal', 'Project Proposal'), ('documentation', 'Documentation'), ('presentation', 'Presentation'), ('report', 'Report'), ('other', 'Other')], default='other', max_length=50)),
                ('file', models.FileField(blank=True, help_text='Uploaded document file', null=True, upload_to='team_documents/%Y/%m/')),
                ('file_name', models.CharField(max_length=255)),
                ('file_data', models.BinaryField(blank=True, null=True)),
                ('file_size', models.IntegerField()),
                ('mime_type', models.CharField(max_length=100)),
                ('description', models.TextField(blank=True, null=True)),
                ('uploaded_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='documents', to='student_teams.studentteam')),
                ('uploaded_by', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='uploaded_documents', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'team_documents_teamdocument',
                'ordering': ['-uploaded_at'],
            },
        ),
    ]
