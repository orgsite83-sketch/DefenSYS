"""Validated document requirements, shared by Capstone and PIT setup."""
import re
from copy import deepcopy
from django.core.exceptions import ValidationError


def with_concept_papers(items, config):
    """Add the default once; existing concept documents keep their authored settings."""
    items = deepcopy(items)
    if not config.get('enabled') or any((d.get('file_policy') or {}).get('mode') == 'concepts' for d in items):
        return items
    used = {d.get('deliverable_id') for d in items}
    number, suffix = 'CONCEPT_PAPERS', 1
    while number in used:
        suffix += 1
        number = f'CONCEPT_PAPERS_{suffix}'
    items.append({'deliverable_id': number, 'label': 'Concept Papers', 'deliverable_type': 'pre',
        'required': True, 'requirement_timing': 'scheduling', 'deadline_hours_before': 24,
        'display_order': max((d.get('display_order', 0) for d in items), default=0) + 1,
        'file_format': 'pdf', 'is_defense_material': True,
        'file_policy': {'mode': 'concepts', 'slots': [
            {'key': 'paper', 'label': 'Concept paper', 'file_format': 'pdf', 'required': True}]}})
    return items


def validate_file_policy(value):
    if not isinstance(value, dict):
        raise ValidationError('Document settings must be an object.')
    mode = value.get('mode', 'single')
    if mode not in ('single', 'named', 'multiple', 'concepts'):
        raise ValidationError('Choose single, named, multiple, or concept documents.')
    slots = value.get('slots', [])
    if not isinstance(slots, list) or len(slots) > 20:
        raise ValidationError('Configure up to 20 named documents.')
    keys = set()
    for slot in slots:
        if not isinstance(slot, dict):
            raise ValidationError('Each document needs a key and label.')
        key = slot.get('key', '')
        if not isinstance(key, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,40}', key) or key in keys:
            raise ValidationError('Document keys must be unique letters, numbers, dashes or underscores.')
        keys.add(key)
        if not isinstance(slot.get('label'), str) or not slot['label'].strip() or len(slot['label']) > 180:
            raise ValidationError('Enter a document label of up to 180 characters.')
        from defense.stages.models import StageDeliverable
        if slot.get('file_format', 'any') not in dict(StageDeliverable.FORMAT_CHOICES):
            raise ValidationError('Choose a supported document format.')
        if not isinstance(slot.get('required', True), bool):
            raise ValidationError('Required must be true or false.')
    if mode == 'named' and (not slots or not any(s.get('required', True) for s in slots)):
        raise ValidationError('Add at least one required named document.')
    if mode == 'concepts' and slots and not any(s.get('required', True) for s in slots):
        raise ValidationError('Require at least one document for every concept.')
    if mode == 'multiple':
        minimum, maximum = value.get('min_files', 1), value.get('max_files', 10)
        if (type(minimum) is not int or type(maximum) is not int
                or not 1 <= minimum <= maximum <= 50):
            raise ValidationError('Choose file limits between 1 and 50, with minimum no greater than maximum.')
    return value


def validate_concept_config(value):
    if not isinstance(value, dict) or not isinstance(value.get('enabled', False), bool):
        raise ValidationError('Choose whether this stage includes concept selection.')
    count = value.get('required_count', 3)
    if type(count) is not int or not 1 <= count <= 10:
        raise ValidationError('Require between 1 and 10 concepts.')
    if value.get('review_policy', 'replacement') not in ('replacement', 'always', 'panel_requested'):
        raise ValidationError('Choose a valid re-defense review policy.')
    if value.get('score_carryover', 'reassess') not in ('reassess', 'retain'):
        raise ValidationError('Choose whether repeat attempts require fresh adviser and peer assessments.')
    return {'required_count': 3, **value} if value.get('enabled') else value
