import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('user_management', '0002_facultyroleassignment'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='StudentAcademicRecord',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('year_level', models.CharField(choices=[('1st Year', '1st Year'), ('2nd Year', '2nd Year'), ('3rd Year', '3rd Year'), ('4th Year', '4th Year')], max_length=20)),
                ('action', models.CharField(choices=[('manual', 'Manual'), ('promote', 'Promote'), ('retain', 'Retain')], default='manual', max_length=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('rolled_from', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='rollover_children', to='user_management.studentacademicrecord')),
                ('semester', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='student_records', to='academic_period_management.semester')),
                ('student', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='academic_records', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'student_academic_records_studentacademicrecord',
                'ordering': ['-created_at', 'student__username'],
                'constraints': [
                    models.UniqueConstraint(fields=('student', 'semester'), name='unique_student_record_per_semester'),
                ],
            },
        ),
    ]
