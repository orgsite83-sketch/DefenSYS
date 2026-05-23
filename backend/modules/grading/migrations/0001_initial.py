import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('defense', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Rubric',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=160)),
                ('scope', models.CharField(choices=[('capstone', 'Capstone'), ('pit', 'PIT')], default='capstone', max_length=20)),
                ('event_name', models.CharField(blank=True, max_length=120)),
                ('evaluation_type', models.CharField(choices=[('panel', 'Panel'), ('adviser', 'Adviser'), ('peer', 'Peer')], max_length=20)),
                ('scale', models.CharField(choices=[('5-Point Scale', '5-Point Scale'), ('10-Point Scale', '10-Point Scale'), ('100-Point Scale', '100-Point Scale')], default='10-Point Scale', max_length=30)),
                ('status', models.CharField(choices=[('draft', 'Draft'), ('published', 'Published')], default='draft', max_length=20)),
                ('is_locked', models.BooleanField(default=False)),
                ('panel_weight', models.PositiveSmallIntegerField(default=50)),
                ('adviser_weight', models.PositiveSmallIntegerField(default=30)),
                ('peer_weight', models.PositiveSmallIntegerField(default=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('created_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_rubrics', to=settings.AUTH_USER_MODEL)),
                ('defense_stage', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='rubrics', to='defense.defensestage')),
                ('semester', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='rubrics', to='academic_period_management.semester')),
            ],
            options={
                'db_table': 'rubric_engine_rubric',
                'ordering': ['-updated_at', 'name'],
            },
        ),
        migrations.CreateModel(
            name='RubricCriterion',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=160)),
                ('description', models.TextField(blank=True)),
                ('scale', models.CharField(choices=[('5-Point Scale', '5-Point Scale'), ('10-Point Scale', '10-Point Scale'), ('100-Point Scale', '100-Point Scale')], default='10-Point Scale', max_length=30)),
                ('max_score', models.PositiveSmallIntegerField(default=10)),
                ('weight', models.DecimalField(decimal_places=2, default=1, max_digits=5)),
                ('display_order', models.PositiveSmallIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('rubric', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='criteria', to='grading.rubric')),
            ],
            options={
                'db_table': 'rubric_engine_rubriccriterion',
                'ordering': ['display_order', 'id'],
            },
        ),
        migrations.AddIndex(
            model_name='rubric',
            index=models.Index(fields=['scope', 'status'], name='rubric_engi_scope_11d033_idx'),
        ),
        migrations.AddIndex(
            model_name='rubric',
            index=models.Index(fields=['evaluation_type'], name='rubric_engi_evaluat_c19eb7_idx'),
        ),
    ]
