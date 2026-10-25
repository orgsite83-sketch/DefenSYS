"""Semester calendar rules shared by period management and defense scheduling."""
from datetime import datetime
from zoneinfo import ZoneInfo

from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from .models import Semester


def validate_calendar(starts_on, ends_on, *, required=True):
    if starts_on is None and ends_on is None and not required:
        return
    errors = {}
    if starts_on is None:
        errors['starts_on'] = 'Choose a start date.'
    if ends_on is None:
        errors['ends_on'] = 'Choose an end date.'
    if not errors and starts_on >= ends_on:
        errors['ends_on'] = 'End date must be after start date.'
    if errors:
        raise ValidationError(errors)


def validate_defense_date(semester, scheduled_date, *, field='scheduled_date', lock=False):
    """Validate the final local calendar day; always read the latest period."""
    if semester.pk:
        query = Semester.objects.select_for_update() if lock else Semester.objects
        semester = query.get(pk=semester.pk)
    if not semester.starts_on or not semester.ends_on:
        raise ValidationError({field: 'Set this semester’s start and end dates in Academic Periods before scheduling.'})
    if not semester.starts_on <= scheduled_date <= semester.ends_on:
        raise ValidationError({field: (
            f'Defense date must fall between {semester.starts_on} and {semester.ends_on} '
            f'for {semester.display_name}.'
        )})
    return semester


def calendar_schedule_issues(semester):
    """Report existing mismatches without rewriting or hiding their records."""
    if not semester.starts_on or not semester.ends_on:
        return {'calendar_configured': False, 'out_of_range_count': 0, 'schedule_ids': []}
    schedules = semester.defense_schedules.filter(
        Q(scheduled_date__lt=semester.starts_on) | Q(scheduled_date__gt=semester.ends_on)
    ).order_by('pk')
    return {'calendar_configured': True, 'out_of_range_count': schedules.count(),
            'schedule_ids': list(schedules.values_list('pk', flat=True))}


def schedule_time_payload(schedule):
    """Transmit an unambiguous institutional time and a real-time reference."""
    stamp = datetime.combine(schedule.scheduled_date, schedule.start_time,
                             tzinfo=ZoneInfo('Asia/Manila'))
    return {'scheduled_at': stamp.isoformat(), 'server_now': timezone.now().isoformat(),
            'semester_id': schedule.semester_id,
            'semester_starts_on': schedule.semester.starts_on.isoformat() if schedule.semester.starts_on else None,
            'semester_ends_on': schedule.semester.ends_on.isoformat() if schedule.semester.ends_on else None,
            'semester_label': schedule.semester.display_name + (' · Historical' if not schedule.semester.is_active else '')}
