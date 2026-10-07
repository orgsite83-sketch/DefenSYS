from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('repository', '0015_remove_archiveentry_unique_archive_entry_per_academic_year_and_more')]
    operations = [
        migrations.AddField(model_name=name, name='classification',
            field=models.JSONField(blank=True, default=dict,
                help_text='Versioned model result, status and supporting document passages'))
        for name in ('archiveentry', 'deliverablesubmission', 'deliverablesubmissionfile')
    ]
