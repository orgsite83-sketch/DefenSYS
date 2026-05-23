from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import display_name, vault_unlocked
from repository.entry_payloads import empty_ml_fields, ml_fields_from
from repository.vault.models import VaultEntry
from repository.vault.services import CAPSTONE_RESTRICTED_IDS

from .trail import audit_trail


def _submission_kind_for_deliverable(submission):
    if submission.deliverable_type == DeliverableSubmission.TYPE_VAULT:
        return 'vault'
    return 'pre'


def _missing_capstone_entry(team, stage_label, definition, request=None):
    is_vault = definition['type'] == DeliverableSubmission.TYPE_VAULT
    locked = is_vault and not vault_unlocked(team, stage_label)
    status = 'Locked' if locked else 'Missing required'
    return {
        'id': f'missing-{team.id}-{stage_label}-{definition["id"]}',
        'source_id': None,
        'type': VaultEntry.TYPE_CAPSTONE,
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
        'submission_kind': 'vault' if is_vault else 'pre',
        'deliverable_type': definition['type'],
        'is_restricted_vault': definition['id'] in CAPSTONE_RESTRICTED_IDS,
        'vault_locked': locked,
        'is_missing': True,
        'uploaded_by': '',
        'uploaded_at': None,
        **empty_ml_fields(),
        'can_override': False,
        'audit_trail': [],
        'vault_note': definition.get('vault_note', ''),
    }


def capstone_vault_entry_payload(entry, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = entry.team
    payload = {
        'id': f'capstone-vault-{entry.id}',
        'source_id': entry.id,
        'type': VaultEntry.TYPE_CAPSTONE,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': resolve_uploaded_file_url(request, entry.file) if entry.file else '',
        'has_file': bool(entry.file),
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
        'course_code': entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'Admin',
        'uploaded_at': entry.uploaded_at,
        'submission_kind': 'archive',
        'deliverable_type': '',
        'is_restricted_vault': False,
        'vault_locked': False,
        'is_missing': False,
        'can_override': False,
        'audit_trail': [],
    }
    payload.update(ml_fields_from(entry) if include_ml else empty_ml_fields())
    if include_audit_trail:
        payload['audit_trail'] = audit_trail(VaultEntry.TYPE_CAPSTONE, entry.id, entry.file_name)
    return payload


def pit_entry_payload(entry, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = entry.team
    payload = {
        'id': f'pit-{entry.id}',
        'source_id': entry.id,
        'type': VaultEntry.TYPE_PIT,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': resolve_uploaded_file_url(request, entry.file) if entry.file else '',
        'has_file': bool(entry.file),
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
        'course_code': entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
        'uploaded_at': entry.uploaded_at,
        'submission_kind': 'pit',
        'deliverable_type': '',
        'is_restricted_vault': False,
        'vault_locked': False,
        'is_missing': False,
        'can_override': True,
        'audit_trail': [],
    }
    payload.update(ml_fields_from(entry) if include_ml else empty_ml_fields())
    if include_audit_trail:
        payload['audit_trail'] = audit_trail(VaultEntry.TYPE_PIT, entry.id, entry.file_name)
    return payload


def capstone_entry_payload(submission, request=None, *, include_ml=False, include_audit_trail=False):
    from defensys_backend.file_urls import resolve_uploaded_file_url

    team = submission.team
    is_vault = submission.deliverable_type == DeliverableSubmission.TYPE_VAULT
    kind = _submission_kind_for_deliverable(submission)
    payload = {
        'id': f'capstone-{submission.id}',
        'source_id': submission.id,
        'type': VaultEntry.TYPE_CAPSTONE,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'file_url': resolve_uploaded_file_url(request, submission.file) if submission.file else '',
        'has_file': bool(submission.file),
        'deliverable_id': submission.deliverable_id,
        'deliverable_label': submission.label,
        'team_id': team.id,
        'team_name': team.name,
        'project_title': team.project_title,
        'year_level': team.year_level,
        'level': team.level,
        'academic_year': team.semester.school_year.label,
        'semester': team.semester.label,
        'stage': submission.stage_label,
        'course_code': '',
        'status': 'Vault Submission' if is_vault else 'Pre-Defense',
        'submission_kind': kind,
        'deliverable_type': submission.deliverable_type,
        'is_restricted_vault': is_vault and submission.deliverable_id in CAPSTONE_RESTRICTED_IDS,
        'vault_locked': False,
        'is_missing': False,
        'uploaded_by': display_name(submission.uploaded_by) or 'System',
        'uploaded_at': submission.uploaded_at,
        'can_override': False,
        'audit_trail': [],
        'vault_note': '',
    }
    payload.update(ml_fields_from(submission) if include_ml else empty_ml_fields())
    if include_audit_trail:
        payload['audit_trail'] = audit_trail(
            VaultEntry.TYPE_CAPSTONE,
            submission.id,
            submission.file_name,
        )
    return payload
