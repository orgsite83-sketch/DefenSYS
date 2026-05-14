# Generated migration for StageDeliverable model

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('defense_stages', '0001_initial'),
    ]

    operations = [
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
                ('defense_stage', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='deliverables', to='defense_stages.defensestage')),
            ],
            options={
                'ordering': ['display_order', 'deliverable_id'],
            },
        ),
        migrations.AddConstraint(
            model_name='stagedeliverable',
            constraint=models.UniqueConstraint(fields=('defense_stage', 'deliverable_id'), name='unique_deliverable_per_stage'),
        ),
    ]
