from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('repository', '0020_deliverable_archive_context'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliverablesubmission',
            name='is_late',
            field=models.BooleanField(default=False, help_text='True if uploaded after defense start under an authorized late-upload window.'),
        ),
    ]
