# Generated manually

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('authentication_access_control', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='is_uploader',
            field=models.BooleanField(default=False),
        ),
    ]
