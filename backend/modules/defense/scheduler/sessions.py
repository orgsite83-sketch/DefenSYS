"""Date-aware conflict checks shared by session generation and confirmation."""
from datetime import datetime, timedelta

from rest_framework.exceptions import ValidationError

from .models import DefenseSchedule


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
