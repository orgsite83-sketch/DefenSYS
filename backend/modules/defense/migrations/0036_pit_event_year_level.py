"""Classify legacy events only when recorded evidence identifies one PIT year."""
import re
from django.db import migrations, models

YEARS = ('1st Year', '2nd Year', '3rd Year')


def classify_events(apps, schema_editor):
    Event = apps.get_model('defense', 'PitEventGradingConfig')
    Schedule = apps.get_model('defense', 'DefenseSchedule')
    Grade = apps.get_model('grading', 'TeamGrade')
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    alias = schema_editor.connection.alias
    for event in Event.objects.using(alias).all():
        recorded = set(Schedule.objects.using(alias).filter(semester_id=event.semester_id,
            scope='pit', event_name__iexact=event.event_name).values_list('team__year_level', flat=True))
        recorded.update(Grade.objects.using(alias).filter(pit_event_config_id=event.pk)
                        .values_list('team__year_level', flat=True))
        recorded.update(Submission.objects.using(alias).filter(pit_event_config_id=event.pk)
                        .exclude(archive_year_level='').values_list('archive_year_level', flat=True))
        recorded.discard('')
        if not recorded:
            # Rubric ownership and explicit legacy names are migration evidence only.
            owners = {getattr(getattr(r, 'created_by', None), 'pit_lead_year', '')
                      for r in (event.panel_rubric, event.peer_rubric) if r is not None}
            owners.discard('')
            hints = {year for year, words in zip(YEARS, (('1st', 'first'), ('2nd', 'second'), ('3rd', 'third')))
                     if any(re.search(r'\b' + word + r'\b', event.event_name, re.I) for word in words)}
            recorded = owners | hints
        if len(recorded) == 1 and recorded.issubset(YEARS):
            Event.objects.using(alias).filter(pk=event.pk).update(year_level=recorded.pop())


class Migration(migrations.Migration):
    dependencies = [
        ('defense', '0035_defenseschedule_materials_late_upload_until'),
        ('grading', '0019_evaluation_weight_snapshots'),
        ('repository', '0021_deliverablesubmission_is_late'),
    ]
    operations = [
        migrations.AddField(model_name='piteventgradingconfig', name='year_level',
            field=models.CharField(max_length=20, blank=True, default='',
                choices=[(year, year) for year in YEARS],
                help_text='Owning PIT cohort. Unclassified legacy events are hidden from cohort workspaces.')),
        migrations.RunPython(classify_events, migrations.RunPython.noop),
    ]
