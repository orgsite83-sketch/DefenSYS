from django.db import migrations, models


def approve_pending_vault_entries(apps, schema_editor):
    VaultEntry = apps.get_model('repository', 'VaultEntry')
    VaultEntry.objects.filter(status='Pending AI Classification').update(status='Approved')


class Migration(migrations.Migration):

    dependencies = [
        ('repository', '0003_repositoryauditlog'),
    ]

    operations = [
        migrations.AddField(
            model_name='vaultentry',
            name='category',
            field=models.CharField(
                blank=True,
                default='',
                help_text='ML-predicted technology category',
                max_length=100,
            ),
        ),
        migrations.AddField(
            model_name='vaultentry',
            name='category_confidence',
            field=models.FloatField(
                blank=True,
                help_text='Classification confidence score (0-100)',
                null=True,
            ),
        ),
        migrations.AlterField(
            model_name='vaultentry',
            name='status',
            field=models.CharField(
                choices=[
                    ('Pending AI Classification', 'Pending AI Classification'),
                    ('Approved', 'Approved'),
                    ('Needs Revision', 'Needs Revision'),
                ],
                default='Approved',
                max_length=40,
            ),
        ),
        migrations.RunPython(approve_pending_vault_entries, migrations.RunPython.noop),
    ]
