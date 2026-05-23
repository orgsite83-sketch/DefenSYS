from django.db import migrations, models
import django.db.models.deletion


def seed_default_stages(apps, schema_editor):
    DefenseStage = apps.get_model('defense', 'DefenseStage')
    defaults = [
        {
            'label': 'Concept Proposal',
            'code': 'concept-proposal',
            'display_order': 1,
            'description': 'Initial presentation of the project concept, problem statement, and proposed solution.',
        },
        {
            'label': 'Project Proposal',
            'code': 'project-proposal',
            'display_order': 2,
            'description': 'Detailed proposal including methodology, timeline, and technical specifications.',
        },
        {
            'label': 'Final Defense',
            'code': 'final-defense',
            'display_order': 3,
            'description': 'Final presentation of the completed project with full system demonstration.',
        },
    ]
    for item in defaults:
        DefenseStage.objects.get_or_create(
            label=item['label'],
            defaults={
                'code': item['code'],
                'display_order': item['display_order'],
                'description': item['description'],
                'is_active': True,
            },
        )


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name='DefenseStage',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('label', models.CharField(max_length=120, unique=True)),
                ('code', models.SlugField(blank=True, max_length=140, unique=True)),
                ('display_order', models.PositiveSmallIntegerField(default=1)),
                ('description', models.TextField(blank=True)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'db_table': 'defense_stages_stage',
                'ordering': ['display_order', 'label'],
            },
        ),
        migrations.CreateModel(
            name='StageDeliverable',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('deliverable_id', models.CharField(max_length=20)),
                ('label', models.CharField(max_length=180)),
                ('deliverable_type', models.CharField(choices=[('pre', 'Pre-Defense'), ('vault', 'Vault')], default='pre', max_length=20)),
                ('required', models.BooleanField(default=False)),
                ('display_order', models.PositiveSmallIntegerField(default=1)),
                ('vault_note', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('defense_stage', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='deliverables', to='defense.defensestage')),
            ],
            options={
                'db_table': 'defense_stages_stagedeliverable',
                'ordering': ['display_order', 'deliverable_id'],
            },
        ),
        migrations.AddConstraint(
            model_name='stagedeliverable',
            constraint=models.UniqueConstraint(fields=('defense_stage', 'deliverable_id'), name='unique_deliverable_per_stage'),
        ),
        migrations.RunPython(seed_default_stages, migrations.RunPython.noop),
    ]
