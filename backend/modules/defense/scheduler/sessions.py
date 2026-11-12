"""Date-aware conflict checks shared by session generation and confirmation."""
from datetime import date, datetime, time, timedelta

from rest_framework.exceptions import ValidationError

from .models import DefenseSchedule


def session_context(schedule):
    """Configured window context shared by the board, calendar and panelist UI.

    Legacy/manual sessions have no implied AM/PM window. Operationally moved
    hearings do not inherit the old planning window's label or nominal times.
    """
    fallback = {'session_label': '', 'session_start_time': None, 'session_end_time': None,
                'legacy_session_id': str(schedule.legacy_session_id) if schedule.legacy_session_id else None}
    if schedule.scope != 'capstone' or not schedule.planning_batch_id or not schedule.planning_block_key:
        return fallback
    try:
        day, raw_index = schedule.planning_block_key.rsplit(':', 1)
        index = int(raw_index)
        windows = sorted(schedule.planning_batch.inputs['windows'], key=lambda w: time.fromisoformat(w['start_time']))
        if index < 0:
            return fallback
        window = windows[index]
        start = datetime.combine(date.fromisoformat(day), time.fromisoformat(window['start_time']))
        end = datetime.combine(start.date(), time.fromisoformat(window['end_time']))
        actual = datetime.combine(schedule.scheduled_date, schedule.start_time)
        if not start <= actual < actual + timedelta(minutes=schedule.slot_duration) <= end:
            return fallback
    except (ValueError, KeyError, IndexError, TypeError, AttributeError):
        return fallback
    label = 'Morning' if start.hour < 12 else 'Afternoon' if start.hour < 18 else 'Evening'
    return {**fallback, 'session_label': label, 'session_start_time': start.time().isoformat(),
            'session_end_time': end.time().isoformat()}


def validate_plan_conflicts(entries):
    if not entries:
        return
    dates = {entry['scheduled_date'] + timedelta(days=offset)
             for entry in entries for offset in (-1, 0, 1)}
    existing = DefenseSchedule.objects.filter(
        scheduled_date__in=dates, status__in=['scheduled', 'done'],
    ).prefetch_related('panel_assignments', 'guest_invitations')
    reservations = []
    for schedule in existing:
        start = datetime.combine(schedule.scheduled_date, schedule.start_time)
        reservations.append({
            'start': start, 'end': start + timedelta(minutes=schedule.slot_duration),
            'room': schedule.room.strip().casefold(),
            'people': {assignment.panelist_id for assignment in schedule.panel_assignments.all()}
                      | ({schedule.documenter_id} if schedule.documenter_id else set()),
            'externals': {inv.evaluator_id for inv in schedule.guest_invitations.all()
                          if inv.is_active and inv.evaluator_id},
        })
    for entry in entries:
        start = datetime.combine(entry['scheduled_date'], entry['start_time'])
        reservation = {
            'start': start, 'end': start + timedelta(minutes=entry['slot_duration']),
            'room': entry['room'].strip().casefold(),
            'people': {person.pk for person in entry['panelists']}
                      | ({entry['documenter'].pk} if entry.get('documenter') else set()),
            'externals': {person.pk for person in entry.get('external_evaluators', [])},
        }
        for other in reservations:
            if start >= other['end'] or other['start'] >= reservation['end']:
                continue
            if reservation['room'] == other['room']:
                raise ValidationError({'slots': 'A session room overlaps another defense.'})
            if reservation['people'] & other['people'] or reservation['externals'] & other['externals']:
                raise ValidationError({'slots': 'An assigned evaluator or documenter has another defense at this time.'})
        reservations.append(reservation)
