"""Preserve retired grant tables as archives and add the student intake ledger."""
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('student_teams', '0018_pitrosterteamdetails_details_source_event'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]
    operations = [
        migrations.RenameModel('TeamRecoveryAuthorization', 'HistoricalCapstoneRecovery'),
        migrations.AlterModelTable('historicalcapstonerecovery', 'student_teams_teamrecoveryauthorization'),
        migrations.AlterField('historicalcapstonerecovery', 'team', models.ForeignKey(
            on_delete=django.db.models.deletion.CASCADE, related_name='historical_recovery_records', to='student_teams.studentteam')),
        migrations.RenameModel('CapstoneJourney', 'HistoricalCapstoneJourney'),
        migrations.AlterModelTable('historicalcapstonejourney', 'student_teams_capstonejourney'),
        migrations.AlterField('historicalcapstonejourney', 'team', models.OneToOneField(
            on_delete=django.db.models.deletion.CASCADE, related_name='historical_capstone_journey', to='student_teams.studentteam')),
        migrations.AddField('studentteam', 'intake_semester', models.ForeignKey(blank=True, null=True,
            on_delete=django.db.models.deletion.PROTECT, related_name='capstone_intake_teams', to='academic_period_management.semester')),
        migrations.AddField('studentteam', 'previous_team', models.ForeignKey(blank=True, null=True,
            on_delete=django.db.models.deletion.PROTECT, related_name='returning_rosters', to='student_teams.studentteam')),
        migrations.AddField('studentteam', 'participation_review_reason', models.TextField(blank=True, default='')),
        migrations.RemoveConstraint('studentteam', 'unique_team_name_per_level'),
        migrations.AddConstraint('studentteam', models.UniqueConstraint(condition=models.Q(roster_identity__isnull=True),
            fields=('name', 'level', 'semester'), name='unique_team_name_per_level_semester')),
        migrations.CreateModel(name='StudentCapstoneParticipation', fields=[
            ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
            ('number', models.PositiveIntegerField()),
            ('state', models.CharField(choices=[('active', 'Active'), ('failed', 'Failed'), ('completed', 'Completed'), ('needs_review', 'Needs review')], default='active', max_length=20)),
            ('confirmed_at', models.DateTimeField(auto_now_add=True)),
            ('student', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='capstone_participations', to=settings.AUTH_USER_MODEL)),
            ('intake_semester', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='student_capstone_participations', to='academic_period_management.semester')),
            ('previous', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='subsequent_participations', to='student_teams.studentcapstoneparticipation')),
            ('confirmed_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='+', to=settings.AUTH_USER_MODEL)),
        ], options={'ordering': ['student_id', 'number'], 'constraints': [
            models.UniqueConstraint(fields=('student', 'intake_semester'), name='unique_student_capstone_intake'),
            models.UniqueConstraint(fields=('student', 'number'), name='unique_student_capstone_number'),
            models.CheckConstraint(condition=models.Q(number__gte=1), name='positive_capstone_participation'),
        ]}),
        migrations.CreateModel(name='StudentCapstonePlacement', fields=[
            ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
            ('placed_at', models.DateTimeField(auto_now_add=True)),
            ('ended_at', models.DateTimeField(blank=True, null=True)),
            ('snapshot', models.JSONField(blank=True, default=dict)),
            ('participation', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='placements', to='student_teams.studentcapstoneparticipation')),
            ('team', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='student_placements', to='student_teams.studentteam')),
        ], options={'ordering': ['placed_at', 'id'], 'constraints': [
            models.UniqueConstraint(condition=models.Q(ended_at__isnull=True), fields=('participation',), name='one_active_capstone_placement'),
        ]}),
    ]
