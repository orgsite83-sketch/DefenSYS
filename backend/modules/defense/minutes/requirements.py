"""Stage requirements backed by authoritative minutes, never student uploads."""

from defense.scheduler.models import DefenseSchedule
from .models import DefenseMinutes


def minutes_definition(stage):
    if not stage or not stage.minutes_required:
        return None
    return {
        'id': stage.minutes_deliverable_id, 'deliverable_id': stage.minutes_deliverable_id,
        'label': stage.minutes_deliverable_label or f'Signed Minutes - {stage.label}',
        'type': 'system', 'deliverable_type': 'system', 'source': 'defense_minutes',
        'responsible': 'Assigned documenter', 'required': True, 'file_format': 'pdf',
        'is_restricted': True, 'completion_rule': 'All required signatures completed',
    }


def minutes_complete(minutes):
    return bool(
        minutes and minutes.status == DefenseMinutes.STATUS_COMPLETED and minutes.pdf_file
        and minutes.documenter_signed_at and minutes.adviser_signed_at and minutes.chairman_signed_at
    )


def minutes_record(schedule):
    minutes = getattr(schedule, 'minutes', None)
    complete = minutes_complete(minutes)
    status = minutes.status if minutes else 'not_started'
    labels = {
        'not_started': 'Awaiting documenter', 'draft': 'Draft - documenter editing',
        'submitted': 'Awaiting adviser signature', 'adviser_signed': 'Awaiting chairman signature',
        'completed': 'Finalized' if complete else 'Signed PDF pending',
    }
    return {
        'schedule_id': schedule.pk, 'minutes_id': minutes.pk if minutes else None,
        'status': status, 'status_label': labels[status], 'completed': complete,
        'pdf_url': f'/api/defense/minutes/{schedule.pk}/pdf/' if complete else None,
        'documenter_name': minutes.documenter_name if minutes else (schedule.documenter.get_full_name() if schedule.documenter else ''),
        'session_status': schedule.status, 'date': str(schedule.scheduled_date),
        'finalized_at': minutes.chairman_signed_at.isoformat() if complete else None,
        'retained_versions': [
            {'id': revision.pk, 'pdf_url': f'/api/defense/minutes/{schedule.pk}/pdf/?revision_id={revision.pk}'}
            for revision in minutes.revisions.all() if revision.pdf_file
        ] if minutes else [],
    }


def stage_minutes_requirement(team, stage):
    if not stage or not team.is_capstone:
        return None
    # An earlier attempt or different semester/project cannot fulfill this one.
    schedules = list(DefenseSchedule.objects.filter(
        team=team, semester_id=team.semester_id, defense_stage=stage,
        project_version=team.project_version, scope=DefenseSchedule.SCOPE_CAPSTONE,
    ).exclude(status=DefenseSchedule.STATUS_CANCELLED).select_related(
        'documenter', 'minutes', 'minutes__documenter_signed_by',
        'minutes__adviser_signed_by', 'minutes__chairman_signed_by',
    ).order_by('-scheduled_date', '-start_time', '-pk'))
    latest = schedules[0] if schedules else None
    if latest and latest.minutes_required is False and not getattr(latest, 'minutes', None):
        return None
    definition = minutes_definition(stage)
    if latest and (latest.requires_minutes or getattr(latest, 'minutes', None)):
        definition = {
            **(definition or {}),
            'id': latest.minutes_deliverable_id or stage.minutes_deliverable_id,
            'label': latest.minutes_deliverable_label or stage.minutes_deliverable_label or f'Signed Minutes - {stage.label}',
            'type': 'system', 'source': 'defense_minutes', 'file_format': 'pdf',
            'required': latest.requires_minutes, 'responsible': 'Assigned documenter',
        }
    if not definition:
        return None
    record = minutes_record(latest) if latest else {
        'schedule_id': None, 'minutes_id': None, 'status': 'not_scheduled',
        'status_label': 'Awaiting defense schedule', 'completed': False, 'pdf_url': None,
        'documenter_name': '', 'session_status': None,
    }
    return {
        **definition, **record, 'uploaded': record['completed'], 'locked': True,
        'can_upload': False, 'can_faculty_review': False,
        'records': [minutes_record(s) for s in schedules if s.requires_minutes or getattr(s, 'minutes', None)],
    }


def signed_minutes_archive_entries():
    """Private institutional archive references the original signed PDF bytes."""
    from django.db.models import Q
    from repository.project_archive.payloads import empty_ml_fields

    minutes_list = DefenseMinutes.objects.filter(
        Q(status=DefenseMinutes.STATUS_COMPLETED) | Q(revisions__pdf_file__isnull=False),
    ).select_related('schedule__team__semester__school_year', 'schedule__defense_stage').prefetch_related('revisions').distinct()
    entries = []
    for minutes in minutes_list:
        schedule = minutes.schedule
        team = schedule.team
        versions = []
        if minutes_complete(minutes):
            versions.append((None, minutes.chairman_signed_at, minutes.project_title))
        for revision in minutes.revisions.all():
            if revision.pdf_file:
                versions.append((revision.pk, revision.created_at, revision.snapshot.get('project_title', minutes.project_title)))
        for revision_id, finalized_at, project_title in versions:
            suffix = f'-revision-{revision_id}' if revision_id else ''
            url = f'/api/defense/minutes/{schedule.pk}/pdf/'
            if revision_id:
                url += f'?revision_id={revision_id}'
            entries.append({
                **empty_ml_fields(),
                'id': f'minutes-{minutes.pk}{suffix}', 'source_id': minutes.pk, 'file_id': None,
                'type': 'capstone', 'source': 'defense_minutes', 'submission_kind': 'post',
                'file_name': f'signed_minutes_{schedule.pk}{suffix}.pdf', 'file_url': url, 'file_size': '', 'has_file': True,
                'deliverable_id': schedule.minutes_deliverable_id or 'MINUTES',
                'deliverable_label': schedule.minutes_deliverable_label or f'Signed Minutes - {minutes.defense_stage_label}',
                'team_id': team.pk, 'team_name': minutes.team_name, 'project_title': project_title,
                'year_level': team.year_level, 'level': team.level,
                'academic_year': team.semester.school_year.label if team.semester else '',
                'semester': team.semester.label if team.semester else '', 'stage': minutes.defense_stage_label,
                'course_code': '', 'status': 'Approved', 'deliverable_type': 'system',
                'deliverable_type_label': 'System generated', 'is_restricted_archive': True,
                'archive_locked': True, 'is_missing': False, 'can_override': False,
                'uploaded_by': minutes.documenter_name, 'uploaded_at': finalized_at,
                'feedback': '', 'audit_trail': [], 'archive_note': 'Official signed defense minutes',
            })
    return entries
