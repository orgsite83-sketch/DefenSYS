from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('authentication_access_control', '0002_user_is_uploader'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='repo_assistant_year',
            field=models.CharField(blank=True, default='', max_length=50),
        ),
    ]
