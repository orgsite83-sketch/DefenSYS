"""Shared checklists use the same document settings as team requirements.

None preserves the original concept-paper checklist. An explicit empty list
means the administrator configured no shared documents for this context.
"""
from copy import deepcopy
import re

from django.core.exceptions import ValidationError

from .document_policy import validate_file_policy


def default_shared_deliverables(config):
    if not (config or {}).get('enabled'):
        return []
    return [
        {'deliverable_id': 'SHARED_CONCEPTS', 'label': 'Concept papers',
         'deliverable_type': 'pre', 'required': True, 'file_format': 'pdf',
         'requirement_timing': 'scheduling', 'deadline_hours_before': 24,
         'is_defense_material': True, 'legacy_purpose': 'proposal',
         'file_policy': {'mode': 'concepts', 'slots': [
             {'key': 'paper', 'label': 'Concept paper', 'file_format': 'pdf', 'required': True}]}},
        {'deliverable_id': 'SHARED_FINAL', 'label': 'Approved concept paper',
         'deliverable_type': 'post', 'required': True, 'file_format': 'pdf',
         'requirement_timing': 'scheduling', 'deadline_hours_before': 24,
         'legacy_purpose': 'final', 'file_policy': {'mode': 'single', 'purpose': 'approved_concept'}},
    ]


def shared_definitions(context):
    configured = getattr(context, 'shared_deliverables', None)
    return deepcopy(default_shared_deliverables(context.concept_config) if configured is None else configured)


def validate_shared_deliverables(value, config, team_deliverables=None):
    from .stages.models import StageDeliverable
    from .deliverable_timing import validate_timing
    from rest_framework.exceptions import ValidationError as ApiValidationError

    if value is None:
        return None
    if not isinstance(value, list) or len(value) > 30:
        raise ValidationError('Configure up to 30 shared deliverables.')
    result, ids = [], set()
    for index, raw in enumerate(value):
        if not isinstance(raw, dict):
            raise ValidationError('Each shared deliverable must be a document requirement.')
        raw = deepcopy(raw)
        team_number = raw.get('team_deliverable_id')
        if team_number is not None:
            if not isinstance(team_number, str) or not team_number.strip() or len(team_number) > 20:
                raise ValidationError('Choose a valid team requirement for the shared submission.')
            if any(row.get('team_deliverable_id') == team_number for row in result):
                raise ValidationError('A team requirement can have only one project-manager submission.')
            if team_deliverables is not None:
                team = next((row for row in team_deliverables if row.get('deliverable_id') == team_number), None)
                if team is None:
                    raise ValidationError('The linked team requirement no longer exists.')
                # One setup entry defines both records. Never allow their format,
                # required slots or review/privacy rules to diverge on an API edit.
                for key in ('label', 'deliverable_type', 'required', 'file_format', 'file_policy',
                            'archive_note', 'archive_file_template', 'is_restricted', 'is_defense_material',
                            'verdict_condition', 'requirement_timing', 'deadline_hours_before'):
                    if key in team:
                        raw[key] = deepcopy(team[key])
                    else:
                        raw.pop(key, None)
        number = raw.get('deliverable_id', '')
        if not isinstance(number, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,40}', number) or number in ids:
            raise ValidationError('Shared deliverable numbers must be unique letters, numbers, dashes or underscores.')
        ids.add(number)
        label = raw.get('label')
        if not isinstance(label, str) or not label.strip() or len(label) > 180:
            raise ValidationError('Enter a shared deliverable name of up to 180 characters.')
        dtype = raw.get('deliverable_type', 'pre')
        if dtype not in ('pre', 'post'):
            raise ValidationError('Choose pre-defense or post-defense for shared deliverables.')
        if type(raw.get('required', False)) is not bool:
            raise ValidationError('Required must be true or false.')
        fmt = raw.get('file_format', 'any')
        if fmt not in dict(StageDeliverable.FORMAT_CHOICES):
            raise ValidationError('Choose a supported shared document format.')
        policy = validate_file_policy(deepcopy(raw.get('file_policy', {})))
        for flag in ('is_restricted', 'is_defense_material'):
            if flag in raw and type(raw[flag]) is not bool:
                raise ValidationError('Shared privacy and defense-material settings must be true or false.')
        template = raw.get('archive_file_template', '')
        if not isinstance(template, str) or len(template) > 255 or len(re.findall(r'\{[a-zA-Z0-9_]+\}', template)) > 3:
            raise ValidationError('Use an archive filename template of up to 255 characters and at most 3 variables.')
        if policy.get('mode') == 'concepts' and not config.get('enabled'):
            raise ValidationError('Enable concept selection before requiring documents for each concept.')
        item = {key: deepcopy(raw[key]) for key in (
            'archive_note', 'archive_file_template', 'is_restricted', 'is_defense_material',
            'verdict_condition', 'requirement_timing', 'deadline_hours_before') if key in raw}
        item.update(deliverable_id=number, label=label.strip(), deliverable_type=dtype,
                    required=raw.get('required', False), file_format=fmt, file_policy=policy,
                    display_order=index + 1)
        if team_number is not None:
            item['team_deliverable_id'] = team_number
        try:
            item.update(validate_timing(item))
        except ApiValidationError as exc:
            raise ValidationError(str(exc.detail)) from exc
        if item.get('verdict_condition', 'all_pass') not in ('all_pass', 'revisions_only'):
            raise ValidationError('Choose a supported post-defense verdict condition.')
        # Only the two original paper definitions can adapt historical papers.
        if number == 'SHARED_CONCEPTS' and dtype == 'pre' and fmt == 'pdf' and policy.get('mode') == 'concepts':
            slots = policy.get('slots') or [{'key': 'paper'}]
            if any(slot['key'] == 'paper' for slot in slots):
                item['legacy_purpose'] = 'proposal'
        if number == 'SHARED_FINAL' and dtype == 'post' and fmt == 'pdf' and policy.get('mode', 'single') == 'single':
            item['legacy_purpose'] = 'final'
        result.append(item)
    return result
