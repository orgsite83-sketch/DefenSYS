from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('authentication_access_control', '0018_audit_review_attribution'),
    ]

    operations = [
        migrations.AddField(
            model_name='systemauditlog',
            name='reference_labels',
            field=models.JSONField(blank=True, default=dict),
        ),
    ]
