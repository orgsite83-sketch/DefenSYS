"""Defense-relative deadlines, independent of scheduling clearance.

The server clock enforces cutoffs on every upload/removal. No background job
is needed to lock a file, and an overdue file never cancels a defense.
"""
from datetime import datetime, timedelta

from django.utils import timezone

from defense.deliverable_timing import TIMING_DEFENSE


def due_before_defense(definition):
    return definition.get('type', definition.get('deliverable_type')) == 'pre' and (
        definition.get('requirement_timing') == TIMING_DEFENSE)


def scheduling_requirement(definition):
    return definition.get('type') == 'pre' and definition.get('required') and not due_before_defense(definition)


def stage_schedule(team, stage_label, *, active_only=False, lock=False):
    from defense.scheduler.models import DefenseSchedule

    schedules = DefenseSchedule.objects.filter(
        team=team, semester_id=team.semester_id, project_version=team.project_version,
        scope='capstone' if team.is_capstone else 'pit',
        status__in=['scheduled'] if active_only else ['scheduled', 'done', 'archived'],
    ).select_related('team', 'defense_stage', 'semester')
    if team.is_capstone:
        schedules = schedules.filter(defense_stage__label=stage_label)
    else:
        schedules = schedules.filter(event_name__iexact=stage_label)
    if lock:
        schedules = schedules.select_for_update(of=('self',))
    return schedules.order_by('-scheduled_date', '-start_time', '-pk').first()


def defense_starts_at(schedule):
    return timezone.make_aware(datetime.combine(schedule.scheduled_date, schedule.start_time),
                               timezone.get_default_timezone())


def deadline_for(definition, schedule):
    if not schedule or not due_before_defense(definition):
        return None
    start = defense_starts_at(schedule)
    deadline = start - timedelta(hours=definition.get('deadline_hours_before', 24))
    if schedule.materials_deadline_override:
        deadline = max(deadline, min(start, schedule.materials_deadline_override))
    return timezone.localtime(deadline, timezone.get_default_timezone())


def valid_material(submission):
    # Metadata-only records cannot satisfy a presentation upload requirement.
    return bool(submission and submission.file and submission.status != 'rejected')


def material_row_state(definition, submission, schedule, *, now=None):
    now = now or timezone.now()
    deadline = deadline_for(definition, schedule)
    valid = valid_material(submission)
    closed = bool(schedule and (schedule.status != 'scheduled' or (deadline and now >= deadline)))
    return {
        'requirement_timing': definition.get('requirement_timing', 'scheduling'),
        'deadline_hours_before': definition.get('deadline_hours_before', 24),
        'due_at': deadline.isoformat() if deadline else None,
        'deadline_passed': bool(deadline and now >= deadline),
        'materials_submitted': valid,
        'materials_status': ('submitted' if valid else
                             'awaiting_schedule' if not schedule else
                             'overdue' if closed and schedule.status == 'scheduled' else
                             'missing' if closed else
                             'needs_revision' if submission and submission.status == 'rejected' else 'pending'),
        'upload_lock_reason': ('The submission deadline has passed. Ask an administrator to extend it.'
                               if closed and schedule.status == 'scheduled' else
                               'This defense is complete; its presentation files are locked.' if closed else ''),
    }


def materials_readiness(schedule, *, definitions=None, submitted=None, now=None):
    from .services import get_deliverable_definitions_for_scope

    if definitions is None:
        definitions = get_deliverable_definitions_for_scope(schedule.scope, schedule.semester_id, schedule.stage_label) if schedule else []
    if submitted is None:
        from .models import DeliverableSubmission
        submitted = {item.deliverable_id: item for item in DeliverableSubmission.all_objects.filter(
            team_id=schedule.team_id, stage_label__iexact=schedule.stage_label,
            project_version=schedule.project_version)} if schedule else {}
    required = [item for item in definitions if item.get('required') and due_before_defense(item)]
    now = now or timezone.now()
    rows = [{'id': item['id'], 'label': item['label'],
             **material_row_state(item, submitted.get(item['id']), schedule, now=now)} for item in required]
    missing = [item for item in rows if not item['materials_submitted']]
    overdue = [item for item in missing if item['materials_status'] == 'overdue']
    return {
        'status': 'not_required' if not rows else 'awaiting_schedule' if not schedule else
                  'ready' if not missing else 'overdue' if overdue else 'pending',
        'required_total': len(rows), 'submitted_total': len(rows) - len(missing),
        'missing': missing, 'overdue': overdue,
        'next_deadline': min((item['due_at'] for item in missing if item['due_at']), default=None),
        'deadline_override': schedule.materials_deadline_override.isoformat() if schedule and schedule.materials_deadline_override else None,
        'deadline_reason': schedule.materials_deadline_reason if schedule else '',
        'items': rows,
        'defense_starts_at': defense_starts_at(schedule).isoformat() if schedule else None,
    }


def ensure_material_editable(team, stage_label, definition, *, lock=False):
    schedule = stage_schedule(team, stage_label, lock=lock)
    if schedule is None:
        # Students can prepare early; their cutoff is known once scheduled.
        from .services import is_stage_defense_done
        if is_stage_defense_done(team, stage_label):
            raise PermissionError('Presentation files for a completed defense are locked.')
        return
    deadline = deadline_for(definition, schedule)
    if schedule.status != 'scheduled':
        raise PermissionError('Presentation files for a completed defense are locked.')
    if timezone.now() >= deadline:
        raise PermissionError('The submission deadline has passed. Ask an administrator to extend it.')


def validate_material_file(definition, file_name, file):
    from pathlib import PurePath

    if file is None or not file.size:
        raise ValueError('Choose a nonempty file for this defense requirement.')
    formats = {
        'pdf': {'.pdf'}, 'presentation': {'.pptx', '.ppt', '.pdf'},
        'document': {'.docx', '.doc', '.pdf'}, 'spreadsheet': {'.xlsx', '.xls', '.csv'},
        'video': {'.mp4', '.mov', '.webm'}, 'image': {'.png', '.jpg', '.jpeg', '.svg'},
        'archive': {'.zip', '.rar', '.7z'}, 'audio': {'.mp3', '.wav', '.aac'},
    }
    extensions = formats.get(definition.get('file_format'))
    if extensions and (PurePath(file_name).suffix.lower() not in extensions or
                       PurePath(file.name).suffix.lower() not in extensions):
        raise ValueError('This deliverable requires a file in its configured format.')
