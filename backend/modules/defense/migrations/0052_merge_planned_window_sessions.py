"""Unify automatic-planning windows while retaining old IDs for links/recovery."""
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from django.db import migrations, models


def merge_window_sessions(apps, schema_editor):
    Schedule = apps.get_model('defense', 'DefenseSchedule')
    database = schema_editor.connection.alias
    candidates, memberships = defaultdict(list), defaultdict(set)
    schedules = Schedule.objects.using(database).filter(
        planning_batch_id__isnull=False,
    ).exclude(planning_block_key='').select_related('planning_batch').order_by('scheduled_date', 'start_time', 'pk')
    for schedule in schedules.iterator():
        try:
            inputs = schedule.planning_batch.inputs
            day, raw_index = schedule.planning_block_key.rsplit(':', 1)
            index = int(raw_index)
            if index < 0 or schedule.scope != 'capstone':
                continue
            windows = sorted(inputs['windows'], key=lambda w: time.fromisoformat(w['start_time']))
            window = windows[index]
            start = datetime.combine(date.fromisoformat(day), time.fromisoformat(window['start_time']))
            end = datetime.combine(start.date(), time.fromisoformat(window['end_time']))
            actual = datetime.combine(schedule.scheduled_date, schedule.start_time)
            if (not start <= actual < actual + timedelta(minutes=schedule.slot_duration) <= end
                    or schedule.room != inputs['room']
                    or schedule.semester_id != int(inputs['semester_id'])
                    or schedule.defense_stage_id != int(inputs['defense_stage_id'])):
                continue
        except (ValueError, KeyError, IndexError, TypeError, AttributeError):
            continue
        key = (schedule.planning_batch_id, schedule.planning_block_key, schedule.semester_id,
               schedule.scope, schedule.defense_stage_id, schedule.event_name, schedule.room)
        candidates[key].append(schedule)
        memberships[schedule.session_id].add(key)

    # Do not alias an ID also used by a moved or unrelated hearing. Repair only
    # complete, proven window memberships without splitting an existing session.
    candidate_ids = {s.pk for group in candidates.values() for s in group}
    blocked = set(Schedule.objects.using(database).filter(session_id__in=list(memberships))
                  .exclude(pk__in=candidate_ids).values_list('session_id', flat=True))
    for key, group in candidates.items():
        if any(s.session_id in blocked or len(memberships[s.session_id]) != 1 for s in group):
            continue
        canonical = group[0].session_id
        for schedule in group:
            if schedule.session_id != canonical and schedule.legacy_session_id is None:
                Schedule.objects.using(database).filter(pk=schedule.pk).update(
                    session_id=canonical, legacy_session_id=schedule.session_id)


def restore_window_sessions(apps, schema_editor):
    Schedule = apps.get_model('defense', 'DefenseSchedule')
    Schedule.objects.using(schema_editor.connection.alias).filter(legacy_session_id__isnull=False).update(
        session_id=models.F('legacy_session_id'), legacy_session_id=None)


class Migration(migrations.Migration):
    dependencies = [('defense', '0051_defenseschedule_planning_block_key_and_more')]
    operations = [
        migrations.AddField(model_name='defenseschedule', name='legacy_session_id',
                            field=models.UUIDField(blank=True, db_index=True, editable=False, null=True)),
        migrations.RunPython(merge_window_sessions, restore_window_sessions),
    ]
