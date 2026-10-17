from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import display_name, archive_unlocked
from repository.entry_payloads import empty_ml_fields, ml_fields_from
from repository.archive.models import ArchiveEntry

from .trail import audit_trail


def _submission_kind_for_deliverable(submission):
    if submission.deliverable_type == DeliverableSubmission.TYPE_POST:
        return 'post'
    return 'pre'


def _submission_archive_context(submission):
    team = submission.team
    semester = submission.archive_semester or (team.semester if team else None)
    return {
        'team_name': submission.archive_team_name or (team.name if team else ''),
        'project_title': submission.archive_project_title or (team.project_title if team else ''),
        'year_level': submission.archive_year_level or (team.year_level if team else ''),
        'level': submission.archive_team_level or (team.level if team else ''),
        'academic_year': semester.school_year.label if semester else '',
        'semester': semester.label if semester else '',
        'pit_event_config_id': submission.pit_event_config_id,
    }


def _missing_capstone_entry(team, stage_label, definition, request=None):
    is_post = definition['type'] == DeliverableSubmission.TYPE_POST
    locked = is_post and not archive_unlocked(team, stage_label)
    status = 'Locked' if locked else 'Missing required'
    return {
        'id': f'missing-{team.id}-{stage_label}-{definition["id"]}',
        'source_id': None,
        'type': ArchiveEntry.TYPE_CAPSTONE,
        'file_name': '',
        'file_size': 0,
        'file_url': '',
        'has_file': False,
        'deliverable_id': definition['id'],
        'deliverable_label': definition['label'],
        'team_id': team.id,
        'team_name': team.name,
        'project_title': team.project_title,
        'year_level': team.year_level,
        'level': team.level,
        'academic_year': team.semester.school_year.label,
        'semester': team.semester.label,
        'stage': stage_label,
        'course_code': '',
        'status': status,
        'submission_kind': 'post' if is_post else 'pre',
        'deliverable_type': definition['type'],
        'is_restricted_archive': definition.get('is_restricted', False),
        'archive_locked': locked,
        'is_missing': True,
        'uploaded_by': '',
        'uploaded_at': None,
        **empty_ml_fields(),
        'can_override': False,
        'audit_trail': [],
        'archive_note': definition.get('archive_note', ''),
    }


def capstone_archive_entry_payload(entry, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = entry.team
    payload = {
        'id': f'capstone-vault-{entry.id}',
        'source_id': entry.id,
        'type': ArchiveEntry.TYPE_CAPSTONE,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': resolve_uploaded_file_url(request, entry.file) if entry.file else '',
        'has_file': bool(entry.file or entry.file_name),
        'deliverable_id': '',
        'deliverable_label': entry.file_name,
        'team_id': entry.team_id,
        'team_name': entry.team_name or (team.name if team else 'Unmatched'),
        'project_title': (
            entry.metadata.get('project_title', '')
            if isinstance(entry.metadata, dict)
            else ''
        ) or (team.project_title if team else ''),
        'year_level': entry.year_level or (team.year_level if team else ''),
        'level': team.level if team else '',
        'academic_year': entry.academic_year,
        'semester': entry.semester_label,
        'stage': entry.stage_label,
        'pit_event_config_id': None,
        'course_code': entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'Admin',
        'uploaded_at': entry.uploaded_at,
        'submission_kind': 'post',
        'deliverable_type': '',
        'is_restricted_archive': False,
        'archive_locked': False,
        'is_missing': False,
        'can_override': True,
        'feedback': entry.metadata.get('feedback', '') if isinstance(entry.metadata, dict) else '',
        'audit_trail': [],
    }
    payload.update(ml_fields_from(entry) if include_ml else empty_ml_fields())
    if include_audit_trail:
        payload['audit_trail'] = audit_trail(ArchiveEntry.TYPE_CAPSTONE, entry.id, entry.file_name)
    return payload


def pit_entry_payload(entry, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = entry.team
    payload = {
        'id': f'pit-{entry.id}',
        'source_id': entry.id,
        'type': ArchiveEntry.TYPE_PIT,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': resolve_uploaded_file_url(request, entry.file) if entry.file else '',
        'has_file': bool(entry.file or entry.file_name),
        'deliverable_id': '',
        'deliverable_label': entry.file_name,
        'team_id': entry.team_id,
        'team_name': entry.team_name or (entry.team.name if entry.team else 'Unmatched'),
        'project_title': entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else '',
        'year_level': entry.year_level or (team.year_level if team else ''),
        'level': team.level if team else entry.year_level or '',
        'academic_year': entry.academic_year,
        'semester': entry.semester_label,
        'stage': entry.stage_label or entry.course_code,
        'pit_event_config_id': entry.pit_event_config_id,
        'course_code': entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
        'uploaded_at': entry.uploaded_at,
        'submission_kind': 'pit',
        'deliverable_type': '',
        'is_restricted_archive': False,
        'archive_locked': False,
        'is_missing': False,
        'can_override': True,
        'feedback': entry.metadata.get('feedback', '') if isinstance(entry.metadata, dict) else '',
        'audit_trail': [],
    }
    payload.update(ml_fields_from(entry) if include_ml else empty_ml_fields())
    if include_audit_trail:
        payload['audit_trail'] = audit_trail(ArchiveEntry.TYPE_PIT, entry.id, entry.file_name)
    return payload


def capstone_entry_payload(submission, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = submission.team
    archive_context = _submission_archive_context(submission)
    is_post = submission.deliverable_type == DeliverableSubmission.TYPE_POST
    kind = _submission_kind_for_deliverable(submission)

    is_pit = 'PIT' in archive_context['level']
    entry_type = ArchiveEntry.TYPE_PIT if is_pit else ArchiveEntry.TYPE_CAPSTONE

    is_restricted_archive = False
    if is_post and team:
        if is_pit:
            from defense.scheduler.models import PitEventDeliverable
            is_restricted_archive = PitEventDeliverable.objects.filter(
                deliverable_id=submission.deliverable_id,
                pit_event_config__semester=submission.archive_semester or team.semester,
                pit_event_config__event_name__iexact=submission.stage_label.strip(),
                is_restricted=True
            ).exists()
        else:
            from defense.stages.models import StageDeliverable
            is_restricted_archive = StageDeliverable.objects.filter(
                deliverable_id=submission.deliverable_id,
                defense_stage__label=submission.stage_label,
                is_restricted=True
            ).exists()

    from repository.deliverables.documents import current_files
    files = current_files(submission)

    if not files:
        entry_id = f'pit-deliverable-{submission.id}' if is_pit else f'capstone-{submission.id}'
        status_display = {
            DeliverableSubmission.STATUS_ACCEPTED: 'Approved',
            DeliverableSubmission.STATUS_REJECTED: 'Needs Revision',
            DeliverableSubmission.STATUS_PENDING: 'Pending Review',
        }.get(submission.status, (submission.status or 'Approved').title())
        deliverable_type_label = 'Post-Defense' if is_post else 'Pre-Defense'

        payload = {
            'id': entry_id,
            'source_id': submission.id,
            'file_id': None,
            'type': entry_type,
            'file_name': submission.file_name,
            'file_size': submission.file_size,
            'file_url': resolve_uploaded_file_url(request, submission.file) if submission.file else '',
            'has_file': bool(submission.file or submission.file_name),
            'deliverable_id': submission.deliverable_id,
            'deliverable_label': submission.label,
            'team_id': team.id if team else None,
            **archive_context,
            'stage': submission.stage_label,
            'course_code': '',
            'status': status_display,
            'submission_kind': kind,
            'deliverable_type': submission.deliverable_type,
            'deliverable_type_label': deliverable_type_label,
            'is_restricted_archive': is_restricted_archive,
            'archive_locked': False,
            'is_missing': False,
            'uploaded_by': display_name(submission.uploaded_by) or 'System',
            'uploaded_at': submission.uploaded_at,
            'can_override': True,
            'feedback': submission.feedback or '',
            'file_replacement_unlocked': submission.file_replacement_unlocked,
            'file_replacement_reason': submission.file_replacement_reason,
            'audit_trail': [],
            'archive_note': '',
        }
        payload.update(ml_fields_from(submission) if include_ml else empty_ml_fields())
        if include_audit_trail:
            payload['audit_trail'] = audit_trail(
                entry_type,
                submission.id,
                submission.file_name,
            )
        return [payload]

    payloads = []
    from repository.deliverables.services import definition_for
    managed = bool((definition_for(team, submission.stage_label, submission.deliverable_id) or {}).get('file_policy'))
    for f in files:
        review_status = f.status if managed else submission.status
        entry_id = f'pit-deliverable-{submission.id}-{f.id}' if is_pit else f'capstone-{submission.id}-{f.id}'
        status_display = {
            DeliverableSubmission.STATUS_ACCEPTED: 'Approved',
            DeliverableSubmission.STATUS_REJECTED: 'Needs Revision',
            DeliverableSubmission.STATUS_PENDING: 'Pending Review',
        }.get(review_status, (review_status or 'pending').title())
        deliverable_type_label = 'Post-Defense' if is_post else 'Pre-Defense'

        canonical_name = ''
        if is_post and team:
            from repository.project_archive.services import resolve_archive_file_template
            canonical_name = resolve_archive_file_template(
                '',
                team,
                submission.stage_label,
                (submission.archive_semester or team.semester).label if (submission.archive_semester or team.semester) else '1st Semester',
                deliverable_label=submission.label,
                file_extension=f.file_name.rpartition('.')[2],
            )

        payload = {
            'id': entry_id,
            'source_id': submission.id,
            'file_id': f.id,
            'type': entry_type,
            'file_name': f.file_name,
            'canonical_file_name': canonical_name or f.file_name,
            'file_size': f.file_size,
            'file_url': resolve_uploaded_file_url(request, f.file) if f.file else '',
            'has_file': bool(f.file or f.file_name),
            'deliverable_id': submission.deliverable_id,
            'deliverable_label': submission.label,
            'team_id': team.id if team else None,
            **archive_context,
            'stage': submission.stage_label,
            'course_code': '',
            'status': status_display,
            'submission_kind': kind,
            'deliverable_type': submission.deliverable_type,
            'deliverable_type_label': deliverable_type_label,
            'is_restricted_archive': is_restricted_archive,
            'archive_locked': False,
            'is_missing': False,
            'uploaded_by': display_name(submission.uploaded_by) or 'System',
            'uploaded_at': f.uploaded_at,
            'can_override': True,
            'feedback': (f.feedback if managed else submission.feedback) or '',
            'file_replacement_unlocked': submission.file_replacement_unlocked,
            'file_replacement_reason': submission.file_replacement_reason,
            'audit_trail': [],
            'archive_note': '',
        }
        payload.update(ml_fields_from(f) if include_ml else empty_ml_fields())
        if include_audit_trail:
            payload['audit_trail'] = audit_trail(
                entry_type,
                submission.id,
                f.file_name,
            )
        payloads.append(payload)
    return payloads
