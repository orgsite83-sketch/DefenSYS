from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('repository', '0005_alter_vaultentry_file'),
    ]

    operations = [
        migrations.AddIndex(
            model_name='deliverablesubmission',
            index=models.Index(fields=['team', 'stage_label'], name='capstone_de_team_st_idx'),
        ),
        migrations.AddIndex(
            model_name='vaultentry',
            index=models.Index(fields=['entry_type', 'team'], name='vault_entry_type_team_idx'),
        ),
    ]
