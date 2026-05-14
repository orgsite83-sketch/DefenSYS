from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('defense_scheduler', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='GuestPanelistCode',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('code', models.CharField(db_index=True, editable=False, max_length=16, unique=True)),
                ('guest_name', models.CharField(max_length=150)),
                ('email', models.EmailField(blank=True, max_length=254)),
                ('is_active', models.BooleanField(default=True)),
                ('expires_at', models.DateTimeField(blank=True, null=True)),
                ('used_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('created_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_guest_panelist_codes', to=settings.AUTH_USER_MODEL)),
                ('defense_schedule', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='guest_panelist_codes', to='defense_scheduler.defenseschedule')),
            ],
            options={
                'ordering': ['-created_at'],
                'indexes': [models.Index(fields=['is_active', 'created_at'], name='user_manage_is_acti_1281e1_idx')],
            },
        ),
    ]
