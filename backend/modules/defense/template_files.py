"""Transactional template saves and read-only attachment projections.

Multipart configuration requests wrap the existing setup JSON in `configuration`.
Files are referenced by explicit keys, never by row order. JSON-only clients keep
attachments unchanged. Nothing here records student downloads or template use.
"""
from functools import wraps
from collections.abc import Mapping
import json
import logging
from pathlib import PurePosixPath

from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models.signals import post_delete
from django.dispatch import receiver
from rest_framework.exceptions import ValidationError

from defensys_backend.file_urls import resolve_uploaded_file_url
from defensys_backend.read_projection import read_memoize
from .template_models import DeliverableTemplate

MAX_TEMPLATE_SIZE = 20 * 1024 * 1024
TEMPLATE_EXTENSIONS = frozenset(('docx pdf pptx xlsx csv tsv png jpg jpeg webp gif svg bmp ico '
    'mp4 webm mov m4v avi mkv ogv mp3 wav aac ogg m4a flac wma txt md markdown zip').split())
logger = logging.getLogger(__name__)


def owner_filter(context):
    return {'pit_event_config_id': context.pk} if hasattr(context, 'event_name') else {'defense_stage_id': context.pk}


def delete_unreferenced_file(name):
    if name and not DeliverableTemplate.objects.filter(file=name).exists():
        try:
            default_storage.delete(name)
        except OSError:
            logger.exception('Could not clean up an unused template attachment')


@receiver(post_delete, sender=DeliverableTemplate)
def template_deleted(sender, instance, **kwargs):
    transaction.on_commit(lambda: delete_unreferenced_file(instance.file.name))


def validate_template_file(file):
    name = PurePosixPath(str(file.name).replace('\\', '/')).name
    if not name or len(name) > 255 or any(ord(c) < 32 for c in name):
        raise ValidationError({'template': 'Choose a file with a valid filename of up to 255 characters.'})
    if name.rsplit('.', 1)[-1].lower() not in TEMPLATE_EXTENSIONS:
        raise ValidationError({'template': 'This template file type is not supported.'})
    if not 0 < file.size <= MAX_TEMPLATE_SIZE:
        raise ValidationError({'template': 'Choose a non-empty template of up to 20 MB.'})
    return name


@read_memoize
def template_map(context):
    if context is None:
        return {}
    cached = getattr(context, '_prefetched_objects_cache', {}).get('template_attachments')
    rows = cached if cached is not None else DeliverableTemplate.objects.filter(**owner_filter(context))
    return {(row.requirement_scope, row.deliverable_id): {
        'id': row.pk, 'original_name': row.original_name, 'byte_size': row.byte_size,
        'updated_at': row.updated_at.isoformat(),
        'file_url': resolve_uploaded_file_url(None, row.file),
    } for row in rows}


def template_metadata(context, number, *, shared=False, definitions=None, attachments=None):
    if context is None:
        return None
    attachments = attachments if attachments is not None else template_map(context)
    scope = 'shared' if shared else 'team'
    if shared:
        from .shared_deliverables import shared_definitions
        definitions = definitions if definitions is not None else shared_definitions(context)
        definition = next((row for row in definitions if row['deliverable_id'] == number), {})
        if definition.get('team_deliverable_id'):
            scope, number = 'team', definition['team_deliverable_id']
    return attachments.get((scope, number))


def _definitions(context):
    from .shared_deliverables import shared_definitions
    rows = {('team', row.deliverable_id): {'deliverable_id': row.deliverable_id,
        'file_policy': row.file_policy} for row in context.deliverables.all()}
    shared = shared_definitions(context)
    rows.update({('shared', row['deliverable_id']): row for row in shared})
    return rows


def _assert_editable(context, key, definitions):
    from .configuration_locks import grade_configuration_lock, requirement_has_data, DATA_REASON
    locked, reason = grade_configuration_lock(context)
    if locked:
        raise ValidationError({'template': reason})
    row = definitions.get(key, {})
    if requirement_has_data(context, key[1], policy=row.get('file_policy'), shared=key[0] == 'shared'):
        raise ValidationError({'template': DATA_REASON})


def _apply(context, changes, files, before, prior_rows, written, user):
    definitions = _definitions(context)
    attachments = list(DeliverableTemplate.objects.select_for_update().filter(**owner_filter(context)))
    by_key = {(row.requirement_scope, row.deliverable_id): row for row in attachments}
    by_id = {row.pk: row for row in attachments}
    # Requirement numbers can change while the underlying team row stays put.
    renumbered = {('team', old): ('team', row.deliverable_id)
        for row in context.deliverables.all() if (old := prior_rows.get(row.pk)) and old != row.deliverable_id}
    touched = set()
    sources = set()
    planned = []
    for change in changes:
        if not isinstance(change, dict) or change.get('scope') not in ('team', 'shared'):
            raise ValidationError({'template': 'Choose a valid requirement for the template.'})
        key = (change['scope'], str(change.get('deliverable_id', '')))
        if key not in definitions:
            raise ValidationError({'template': 'The template requirement no longer exists. Refresh setup.'})
        definition = definitions[key]
        if key[0] == 'shared' and definition.get('team_deliverable_id'):
            key = ('team', definition['team_deliverable_id'])
        if key in touched:
            raise ValidationError({'template': 'Only one template operation is allowed per requirement.'})
        touched.add(key)
        action = change.get('action')
        if action not in ('keep', 'replace', 'remove'):
            raise ValidationError({'template': 'Choose keep, replace, or remove for the template.'})
        source_id = change.get('source_id')
        row = by_id.get(source_id) if isinstance(source_id, int) and not isinstance(source_id, bool) else None
        if source_id is not None and row is None:
            raise ValidationError({'template': 'The saved template changed or belongs to another setup.'})
        if source_id is not None and source_id in sources:
            raise ValidationError({'template': 'A saved template can belong to only one setup entry.'})
        if source_id is not None:
            sources.add(source_id)
        row = row or by_key.get(key) or next((by_key[old] for old, new in renumbered.items()
                                           if new == key and old in by_key), None)
        if action == 'keep' and (row is None or (row.requirement_scope, row.deliverable_id) == key):
            continue
        _assert_editable(context, key, definitions)
        if row:
            _assert_editable(context, (row.requirement_scope, row.deliverable_id), before)
        upload_key = change.get('upload_key')
        if action == 'replace' and not isinstance(upload_key, str):
            raise ValidationError({'template': 'Choose a valid upload key for the replacement template.'})
        file = files.get(upload_key) if action == 'replace' else None
        if action == 'replace' and file is None:
            raise ValidationError({'template': 'Select the replacement template again.'})
        name = validate_template_file(file) if file else None
        planned.append((key, action, row, file, name))
    # Validate the entire operation list before touching file storage.
    retained_ids = {row.pk for _, action, row, _, _ in planned if row and action != 'remove'}
    for old, new in renumbered.items():
        row = by_key.get(old)
        if row and row.pk not in retained_ids:
            row.deliverable_id = new[1]
            row.save(update_fields=['deliverable_id'])
    for key, action, row, file, name in planned:
        if action == 'remove':
            if row:
                row.delete()
            continue
        existing = by_key.get(key)
        if existing and row and existing.pk != row.pk:
            existing.delete()
        row = row or DeliverableTemplate(**owner_filter(context))
        old_file = row.file.name if row.file else None
        row.requirement_scope, row.deliverable_id = key
        if file:
            row.original_name, row.byte_size, row.uploaded_by = name, file.size, user
            row.file.save(name, file, save=False)
            written.append(row.file.name)
        row.save()
        if file and old_file:
            transaction.on_commit(lambda name=old_file: delete_unreferenced_file(name))
    for row in DeliverableTemplate.objects.filter(**owner_filter(context)):
        key = (row.requirement_scope, row.deliverable_id)
        if key not in definitions or (key[0] == 'shared' and definitions[key].get('team_deliverable_id')):
            _assert_editable(context, key, before)
            row.delete()


def _refresh_response(value, context, attachments):
    if isinstance(value, list):
        for child in value:
            _refresh_response(child, context, attachments)
    elif isinstance(value, dict):
        if value.get('id') == context.pk and 'deliverables' in value:
            for scope, field in [('team', 'deliverables'), ('shared', 'shared_deliverables')]:
                for row in value.get(field) or []:
                    row['template'] = template_metadata(context, row['deliverable_id'],
                        shared=scope == 'shared', attachments=attachments)
        for child in list(value.values()):
            if isinstance(child, (list, dict)):
                _refresh_response(child, context, attachments)


def template_save(*, pit=False):
    """Keep the setup transaction and any attachment writes atomic together."""
    def decorate(method):
        @wraps(method)
        def wrapped(view, request, *args, **kwargs):
            data, files = request.data, request.FILES.copy()
            if not isinstance(data, Mapping):
                raise ValidationError({'configuration': 'Configuration must be an object.'})
            if 'configuration' in data:
                try:
                    data = json.loads(data['configuration'])
                except (TypeError, ValueError):
                    raise ValidationError({'configuration': 'Enter valid configuration JSON.'})
                if not isinstance(data, dict):
                    raise ValidationError({'configuration': 'Configuration must be an object.'})
                request._full_data = data
            changes = data.get('template_changes', [])
            if not isinstance(changes, list) or len(changes) > 100:
                raise ValidationError({'template_changes': 'Provide up to 100 template operations.'})
            from .stages.models import DefenseStage
            from .scheduler.models import PitEventGradingConfig
            model = PitEventGradingConfig if pit else DefenseStage
            written = []
            try:
                with transaction.atomic():
                    pk = data.get('config_id') if pit else kwargs.get('stage_id')
                    context = model.objects.select_for_update().filter(pk=pk).first() if str(pk).isdigit() else None
                    if pit and context is None and pk is None:
                        context = model.objects.select_for_update().filter(event_name__iexact=data.get('event_name', ''),
                            semester_id=data.get('semester_id'), year_level=data.get('year_level')).first()
                    before = _definitions(context) if context else {}
                    prior = dict(context.deliverables.values_list('pk', 'deliverable_id')) if context else {}
                    response = method(view, request, *args, **kwargs)
                    if response.status_code >= 400:
                        transaction.set_rollback(True)
                        return response
                    result = (response.data or {}).get('config' if pit else 'stage', {})
                    context = model.objects.select_for_update().get(pk=result.get('id') or context.pk)
                    previous_templates = template_map(context)
                    _apply(context, changes, files, before, prior, written, request.user)
                    current_templates = template_map(context)
                    _refresh_response(response.data, context, current_templates)
                    if isinstance(response.data, dict) and 'deliverable_id' in response.data:
                        response.data['template'] = template_metadata(context, response.data['deliverable_id'])
                    if previous_templates != current_templates:
                        from authentication_access_control.audit import log_high_impact_action
                        from authentication_access_control.models import SystemAuditLog
                        log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING,
                            action='deliverable.templates_updated', target=context, actor=request.user,
                            request=request, strict=True, new_values={'templates': list(current_templates.values())})
                    return response
            except Exception:
                for name in written:
                    delete_unreferenced_file(name)
                raise
        return wrapped
    return decorate


def can_read_template(user, attachment):
    """Use the same team and shared memberships as requirement read surfaces."""
    from authentication_access_control.scopes import is_admin_user
    from repository.deliverables.services import team_queryset_for_user
    from repository.deliverables.services import document_context
    from .scheduler.event_scope import require_event_management
    from .configuration_locks import context_filter
    if getattr(user, 'is_guest_panelist', False):
        return False
    if is_admin_user(user):
        return True
    context = attachment.pit_event_config or attachment.defense_stage
    pit = attachment.pit_event_config_id is not None
    if pit:
        from django.core.exceptions import PermissionDenied
        try:
            require_event_management(user, context)
            return True
        except PermissionDenied:
            pass
    teams = team_queryset_for_user(user).select_related('semester')
    teams = teams.filter(level__icontains='PIT', semester=context.semester, year_level=context.year_level) if pit else teams.exclude(level__icontains='PIT')
    for team in teams:
        if not pit:
            from student_teams.capstone_lifecycle import requirements_for
            from student_teams.capstone_context import phase_requirements
            requirements = requirements_for(team) if getattr(user, 'role', '') == 'student' else phase_requirements(team)
            if context.pk not in {row['id'] for row in requirements}:
                continue
        label = context.event_name if pit else context.label
        candidate = document_context(team, label)
        if candidate is None or context_filter(candidate) != context_filter(context):
            continue
        if pit:
            from .scheduler.event_scope import pit_events_for_team
            if not pit_events_for_team(team).filter(pk=context.pk).exists():
                continue
        if attachment.requirement_scope == 'team':
            return context.deliverables.filter(deliverable_id=attachment.deliverable_id).exists()
        from repository.section_concepts.shared_deliverables import resolve, member_access, staff_access
        profile = resolve(team, context)
        if profile and (member_access(user, profile) or staff_access(user, profile)) and any(
                row['deliverable_id'] == attachment.deliverable_id for row in profile['definitions']):
            return True
    return False
