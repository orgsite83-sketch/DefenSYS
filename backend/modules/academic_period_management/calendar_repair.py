"""Explicit, audited demo-date correction; never runs during migrations or reads."""
import json
from pathlib import Path

from django.core.serializers import serialize
from django.core.serializers.json import DjangoJSONEncoder
from django.db import transaction

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defensys_backend.db_guard import assert_safe_for_orm_writes
from .calendar import validate_calendar, validate_defense_date
from .models import Semester


@transaction.atomic
def repair_sample_calendar(*, semester_id, starts_on, ends_on, source_date, target_date,
                           expected_count, actor, reason, backup_path=None, apply=False):
    """Preview by default; applying requires an exact scope and a durable backup."""
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import PanelistGradeSubmission, TeamGrade
    from defense.minutes.models import DefenseMinutes
    validate_calendar(starts_on, ends_on)
    if not starts_on <= target_date <= ends_on:
        raise ValueError('The replacement defense date must fall inside the semester calendar.')
    if source_date == target_date or not reason.strip():
        raise ValueError('Provide distinct source/target dates and a correction reason.')
    if apply:
        assert_safe_for_orm_writes()
        if not backup_path:
            raise ValueError('An existing-record backup path is required when applying.')
        if not (actor and (actor.role == 'admin' or actor.is_superuser)):
            raise ValueError('An administrator must be identified for the correction audit.')
    query = Semester.objects.select_for_update() if apply else Semester.objects
    semester = query.select_related('school_year').get(pk=semester_id)
    schedules = DefenseSchedule.objects.filter(semester=semester, scheduled_date=source_date).order_by('pk')
    if apply:
        schedules = schedules.select_for_update()
    rows = list(schedules)
    if len(rows) != expected_count:
        raise ValueError(f'Expected {expected_count} source schedules; found {len(rows)}. No correction applied.')
    ids = [row.pk for row in rows]
    if (PanelistGradeSubmission.objects.filter(schedule_id__in=ids).exists()
            or DefenseMinutes.objects.filter(schedule_id__in=ids).exists()
            or TeamGrade.all_objects.filter(schedule_id__in=ids, status='published').exists()):
        raise ValueError('Recorded assessments or minutes require the normal historical correction workflow.')
    report = {'semester_id': semester.pk, 'semester': semester.display_name,
              'starts_on': starts_on, 'ends_on': ends_on,
              'source_date': source_date, 'target_date': target_date, 'schedule_ids': ids, 'applied': False}
    if not apply:
        return report
    # Exclusive creation prevents overwriting evidence from an earlier repair.
    backup = Path(backup_path)
    backup.parent.mkdir(parents=True, exist_ok=True)
    with backup.open('x', encoding='utf-8') as stream:
        json.dump({'correction': report, 'reason': reason,
                   'records_before': json.loads(serialize('json', [semester, *rows]))},
                  stream, cls=DjangoJSONEncoder, indent=2)
    old_calendar = {'starts_on': str(semester.starts_on) if semester.starts_on else None,
                    'ends_on': str(semester.ends_on) if semester.ends_on else None}
    semester.starts_on, semester.ends_on = starts_on, ends_on
    semester.save(update_fields=['starts_on', 'ends_on'])
    for row in rows:
        validate_defense_date(semester, target_date)
        row.scheduled_date = target_date
        row.revision += 1
        row.save(update_fields=['scheduled_date', 'revision', 'updated_at'])
        log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='schedule.sample_calendar_corrected', target=row, actor=actor,
            old_values={'scheduled_date': source_date.isoformat()},
            new_values={'scheduled_date': target_date.isoformat(), 'revision': row.revision}, reason=reason, strict=True)
    log_high_impact_action(category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
        action='semester.sample_calendar_configured', target=semester, actor=actor,
        old_values=old_calendar, new_values={'starts_on': starts_on.isoformat(), 'ends_on': ends_on.isoformat()},
        reason=reason, strict=True)
    return {**report, 'applied': True, 'backup': str(backup.resolve())}
