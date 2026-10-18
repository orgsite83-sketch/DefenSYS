"""Defense-relative deadlines, independent of scheduling clearance.

The server clock enforces cutoffs on every upload/removal. No background job
is needed to lock a file, and an overdue file never cancels a defense.
"""
from datetime import datetime, timedelta

from django.db.models import Exists, OuterRef
from django.utils import timezone

from defense.deliverable_timing import TIMING_DEFENSE


def due_before_defense(definition):
    return definition.get('type', definition.get('deliverable_type')) == 'pre' and (
        definition.get('requirement_timing') == TIMING_DEFENSE)


def scheduling_requirement(definition):
    return definition.get('type') == 'pre' and definition.get('required') and not due_before_defense(definition)


def with_material_permissions(queryset):
    """Batch permission facts for schedule lists without per-row queries."""
    from grading.grades.models import PanelistGradeSubmission, TeamGrade

    return queryset.annotate(
        _has_evals=Exists(PanelistGradeSubmission.objects.filter(schedule_id=OuterRef('pk'), is_void=False)),
        _grades_locked=Exists(TeamGrade.all_objects.filter(
            schedule_id=OuterRef('pk'), status__in=TeamGrade.LOCKED_STATUSES)),
    )


def load_material_permissions(schedules):
    """Populate the same facts for callers that already have a list of models."""
    from defense.scheduler.models import DefenseSchedule

    pending = [row for row in schedules if not (hasattr(row, '_has_evals') and hasattr(row, '_grades_locked'))]
    if not pending:
        return
    facts = {row['pk']: row for row in with_material_permissions(
        DefenseSchedule.objects.filter(pk__in={row.pk for row in pending}),
    ).values('pk', '_has_evals', '_grades_locked')}
    for schedule in pending:
        if schedule.pk in facts:
            schedule._has_evals = facts[schedule.pk]['_has_evals']
            schedule._grades_locked = facts[schedule.pk]['_grades_locked']


def material_grades_locked(schedule):
    from grading.grades.models import TeamGrade

    if hasattr(schedule, '_grades_locked'):
        return schedule._grades_locked
    if 'grade_records' in getattr(schedule, '_prefetched_objects_cache', {}):
        return any(grade.status in TeamGrade.LOCKED_STATUSES for grade in schedule.grade_records.all())
    return TeamGrade.all_objects.filter(schedule=schedule, status__in=TeamGrade.LOCKED_STATUSES).exists()


def has_material_evaluations(schedule):
    if hasattr(schedule, '_has_evals'):
        return schedule._has_evals
    if 'panelist_grade_submissions' in getattr(schedule, '_prefetched_objects_cache', {}):
        return any(not row.is_void for row in schedule.panelist_grade_submissions.all())
    return schedule.panelist_grade_submissions.filter(is_void=False).exists()


def current_material_schedule(schedule):
    return (schedule.project_version == schedule.team.project_version
            and schedule.semester_id == schedule.team.semester_id)


def late_upload_window_active(schedule, *, now=None, grades_locked=None):
    if not schedule or schedule.status not in ('scheduled', 'done') or not current_material_schedule(schedule):
        return False
    if not schedule.materials_late_upload_until or (now or timezone.now()) > schedule.materials_late_upload_until:
        return False
    return not (material_grades_locked(schedule) if grades_locked is None else grades_locked)


from defensys_backend.read_projection import read_memoize


@read_memoize(bypass_if=('lock',))
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
    schedules = with_material_permissions(schedules)
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


def material_row_state(definition, submission, schedule, *, now=None, grades_locked=None):
    now = now or timezone.now()
    deadline = deadline_for(definition, schedule)
    valid = valid_material(submission)
    if definition.get('file_policy'):
        from .documents import completeness
        valid = valid and completeness(submission, definition, stage=schedule.defense_stage if schedule else None)
    grades_locked = bool(schedule and (material_grades_locked(schedule) if grades_locked is None else grades_locked))
    late_active = late_upload_window_active(schedule, now=now, grades_locked=grades_locked)
    has_file = bool(submission and submission.file)
    effective_due = schedule.materials_late_upload_until if (late_active and not has_file) else deadline
    closed = bool(schedule and (grades_locked or schedule.status != 'scheduled' or (deadline and now >= deadline))) and not late_active
    is_late = bool(submission and getattr(submission, 'is_late', False))
    return {
        'requirement_timing': definition.get('requirement_timing', 'scheduling'),
        'deadline_hours_before': definition.get('deadline_hours_before', 24),
        'due_at': effective_due.isoformat() if effective_due else (deadline.isoformat() if deadline else None),
        'original_due_at': deadline.isoformat() if deadline else None,
        'deadline_passed': bool(deadline and now >= deadline and not late_active),
        'materials_submitted': valid,
        'is_late': is_late,
        'late_window_active': late_active,
        'materials_status': ('submitted' if valid else
                             'awaiting_schedule' if not schedule else
                             'late_window' if late_active and not has_file else
                             'needs_revision' if late_active and has_file else
                             'overdue' if closed and schedule.status == 'scheduled' else
                             'missing' if closed else
                             'needs_revision' if submission and submission.status == 'rejected' else 'pending'),
        'upload_lock_reason': ('' if (late_active and not has_file) else
                               'Existing submissions are locked to preserve defense evaluations.' if (late_active and has_file) else
                               'Presentation files for finalized grades are locked.' if grades_locked else
                               'The submission deadline has passed. Ask an administrator to extend it.'
                               if closed and schedule.status == 'scheduled' else
                               'This defense is complete; its presentation files are locked.' if closed else ''),
    }


def materials_readiness(schedule, *, definitions=None, submitted=None, now=None):
    from .services import get_deliverable_definitions_for_scope

    if definitions is None:
        definitions = get_deliverable_definitions_for_scope(schedule.scope, schedule.semester_id, schedule.stage_label, year_level=schedule.team.year_level) if schedule else []
    if submitted is None:
        from .models import DeliverableSubmission
        submitted = {item.deliverable_id: item for item in DeliverableSubmission.all_objects.filter(
            team_id=schedule.team_id, stage_label__iexact=schedule.stage_label,
            project_version=schedule.project_version)} if schedule else {}
    required = [item for item in definitions if item.get('required') and due_before_defense(item)]
    now = now or timezone.now()
    has_evals = bool(schedule and has_material_evaluations(schedule))
    grades_locked = bool(schedule and material_grades_locked(schedule))
    rows = [{'id': item['id'], 'label': item['label'],
             **material_row_state(item, submitted.get(item['id']), schedule, now=now, grades_locked=grades_locked)} for item in required]
    missing = [item for item in rows if not item['materials_submitted']]
    overdue = [item for item in missing if item['materials_status'] == 'overdue']
    late_until = schedule.materials_late_upload_until if schedule else None
    late_active = late_upload_window_active(schedule, now=now, grades_locked=grades_locked)
    past_defense = bool(schedule and now >= defense_starts_at(schedule))
    can_manage = bool(schedule and required and current_material_schedule(schedule) and not grades_locked)
    can_extend = bool(can_manage and schedule.status == 'scheduled' and not past_defense and not has_evals)
    can_late_upload = bool(can_manage and schedule.status in ('scheduled', 'done'))
    return {
        'status': 'not_required' if not rows else 'awaiting_schedule' if not schedule else
                  'ready' if not missing else 'late_window' if late_active else 'overdue' if overdue else 'pending',
        'required_total': len(rows), 'submitted_total': len(rows) - len(missing),
        'missing': missing, 'overdue': overdue,
        'next_deadline': min((item['due_at'] for item in missing if item['due_at']), default=None),
        'deadline_override': schedule.materials_deadline_override.isoformat() if schedule and schedule.materials_deadline_override else None,
        'late_upload_until': late_until.isoformat() if late_until else None,
        'late_window_active': late_active,
        'deadline_reason': schedule.materials_deadline_reason if schedule else '',
        'items': rows,
        'defense_starts_at': defense_starts_at(schedule).isoformat() if schedule else None,
        'is_past_defense': past_defense,
        'has_evaluations': has_evals,
        'can_extend_deadline': can_extend,
        'can_open_late_window': can_late_upload,
        'is_locked_historical': grades_locked or (schedule.status == 'archived' if schedule else False),
    }


def ensure_material_editable(team, stage_label, definition, *, lock=False):
    schedule = stage_schedule(team, stage_label, lock=lock)
    if schedule is None:
        # Students can prepare early; their cutoff is known once scheduled.
        from .services import is_stage_defense_done
        if is_stage_defense_done(team, stage_label):
            raise PermissionError('Presentation files for a completed defense are locked.')
        return
    now = timezone.now()
    if schedule.status == 'archived':
        raise PermissionError('Presentation files for an archived defense are locked.')
    if material_grades_locked(schedule):
        raise PermissionError('Presentation files for finalized grades are locked.')
    if late_upload_window_active(schedule, now=now):
        from .models import DeliverableSubmission
        existing = DeliverableSubmission.all_objects.filter(
            team=team, stage_label__iexact=stage_label, deliverable_id=definition['id'],
            project_version=team.project_version,
        ).first()
        if existing and existing.file:
            raise PermissionError('Existing submitted files are locked to protect defense evaluations.')
        return

    deadline = deadline_for(definition, schedule)
    if schedule.status != 'scheduled':
        raise PermissionError('Presentation files for a completed defense are locked.')
    if deadline and now >= deadline:
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
