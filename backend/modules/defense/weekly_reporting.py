"""Managed weekly requirements with independent calendars for each stage."""
from datetime import date, time

from django.db import transaction
from rest_framework.exceptions import ValidationError

from defensys_backend.read_projection import read_memoize

WEEKLY_ID = 'WPR'
WEEKLY_LABEL = 'Weekly Accomplishment Reports'
CALENDAR_FIELDS = ('starts_on', 'total_weeks', 'due_weekday', 'due_time')


@read_memoize
def period_for(period_id):
    from student_teams.weekly_progress.models import WeeklyReportingPeriod
    return WeeklyReportingPeriod.objects.filter(pk=period_id).first() if period_id else None


def policy_payload(stage):
    config = getattr(stage, 'weekly_reporting', None) or {}
    if not config.get('enabled'):
        return {'enabled': False}
    period = period_for(config.get('period_id'))
    if period and period.defense_stage_id != stage.pk:
        period = None
    if period is None:
        return {'enabled': True, **config}
    return {**config, 'starts_on': str(period.starts_on), 'total_weeks': period.total_weeks,
        'due_weekday': period.due_weekday, 'due_time': period.due_time.strftime('%H:%M'),
        'semester_id': period.semester_id, 'defense_stage_id': period.defense_stage_id,
        'timezone': 'Asia/Manila'}


def definition(stage):
    policy = policy_payload(stage)
    if not policy.get('enabled'):
        return None
    return {'id': WEEKLY_ID, 'deliverable_id': WEEKLY_ID, 'label': WEEKLY_LABEL,
        'type': 'pre', 'deliverable_type': 'pre', 'source': 'weekly_reports',
        'required': True, 'requirement_timing': 'scheduling', 'file_format': 'pdf',
        'file_policy': {}, 'weekly_reporting': policy, 'is_restricted': True,
        'is_defense_material': False, 'verdict_condition': 'all_pass'}


def used(period):
    from defense.stages.models import DefenseStage
    from defense.configuration_locks import grade_configuration_lock
    from defense.stages.serializers import check_stage_structure_locked
    if period.reports.exists():
        return True
    for stage in DefenseStage.objects.filter(pk=period.defense_stage_id):
        if grade_configuration_lock(stage)[0] or check_stage_structure_locked(stage)[0]:
            return True
        from student_teams.models import TeamStageProgress
        if TeamStageProgress.all_objects.filter(defense_stage=stage).exclude(status='locked').exists():
            return True
    return False


def validate_configuration(raw, *, stage=None, semester=None):
    from student_teams.weekly_progress.models import WeeklyReportingPeriod
    if not isinstance(raw, dict) or not isinstance(raw.get('enabled', False), bool):
        raise ValidationError({'weekly_reporting': 'Choose whether weekly reports are required.'})
    old = policy_payload(stage)
    if not raw.get('enabled'):
        if old.get('enabled') and (period := period_for(old.get('period_id'))) and used(period):
            raise ValidationError({'weekly_reporting': 'Weekly reporting has recorded use and cannot be disabled.'})
        return {'enabled': False}
    if not semester:
        raise ValidationError({'weekly_reporting': 'Choose the reporting semester.'})
    period = (WeeklyReportingPeriod.objects.filter(semester=semester, defense_stage=stage).first()
        if stage and stage.pk else None)
    try:
        start = date.fromisoformat(str(raw['starts_on']))
        deadline = time.fromisoformat(str(raw['due_time']))
        numbers = {}
        for key in ('due_weekday', 'required_start', 'required_end'):
            value = raw[key]
            if isinstance(value, bool) or str(value).strip() != str(int(value)):
                raise ValueError()
            numbers[key] = int(value)
        # New calendars contain only the administrator's configured weeks. Older
        # clients may still send the removed calendar default; do not adopt it.
        numbers['total_weeks'] = numbers['required_end']
        if not (1 <= numbers['total_weeks'] <= 53 and 0 <= numbers['due_weekday'] <= 6
                and 1 <= numbers['required_start'] <= numbers['required_end'] <= numbers['total_weeks']):
            raise ValueError()
        if deadline.tzinfo or deadline.second or deadline.microsecond:
            raise ValueError()
    except (KeyError, ValueError, TypeError, OverflowError):
        raise ValidationError({'weekly_reporting': 'Enter a start date, weekly deadline, 1-53 reporting weeks, '
            'and a required week range within that period.'})
    clean = {'enabled': True, 'starts_on': str(start), 'due_time': deadline.strftime('%H:%M'), **numbers}
    if raw.get('period_id') and (not period or str(raw['period_id']) != str(period.pk)):
        raise ValidationError({'weekly_reporting': 'The reporting calendar belongs to another stage or semester. Reopen setup.'})
    if period:
        current = {'starts_on': str(period.starts_on), 'total_weeks': period.total_weeks,
            'due_weekday': period.due_weekday, 'due_time': period.due_time.strftime('%H:%M')}
        clean['period_id'] = period.pk
        period_used = used(period)
        # Calendar length is internal historical context once the stage is used.
        # A legacy longer calendar need not shrink on an otherwise unchanged save.
        if period_used:
            clean['total_weeks'] = period.total_weeks
        if any(current[key] != clean[key] for key in CALENDAR_FIELDS) and period_used:
            raise ValidationError({'weekly_reporting': 'Weekly reporting has recorded use and its settings are protected.'})
        if old.get('enabled') and any(old.get(key) != clean.get(key) for key in
                ('required_start', 'required_end')) and period_used:
            raise ValidationError({'weekly_reporting': 'Weekly reporting has recorded use and its settings are protected.'})
    return clean


@transaction.atomic
def save_configuration(stage, raw):
    from academic_period_management.models import Semester
    from student_teams.weekly_progress.models import WeeklyReportingPeriod
    # Serialize calendar creation against concurrent saves of this stage.
    Semester.objects.select_for_update().get(pk=stage.setup_semester_id)
    period = WeeklyReportingPeriod.objects.select_for_update().filter(
        semester=stage.setup_semester, defense_stage=stage).first()
    raw = validate_configuration(raw, stage=stage, semester=stage.setup_semester)
    if not raw.get('enabled'):
        return {}
    if period is None:
        period = WeeklyReportingPeriod(semester=stage.setup_semester, defense_stage=stage)
    for key in CALENDAR_FIELDS:
        setattr(period, key, raw[key])
    period.save()
    return {'enabled': True, 'period_id': period.pk,
        'required_start': raw['required_start'], 'required_end': raw['required_end']}
