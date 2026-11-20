"""Explicit stage revision areas, captured independently of labels and files."""
import re

from django.core.exceptions import ValidationError


def validate_revision_areas(value):
    if not isinstance(value, list) or len(value) > 12:
        raise ValidationError('Configure up to 12 revision areas.')
    result, seen = [], set()
    for item in value:
        if not isinstance(item, dict) or set(item) - {'id', 'label', 'allows_demo'}:
            raise ValidationError('Each revision area needs an identifier, label, and demonstration setting.')
        key, label = item.get('id'), item.get('label')
        if not isinstance(key, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', key) or key in seen:
            raise ValidationError('Revision area identifiers must be unique and contain letters, numbers, underscores, or hyphens.')
        if not isinstance(label, str) or not 1 <= len(label.strip()) <= 80:
            raise ValidationError('Enter a revision area label of up to 80 characters.')
        if not isinstance(item.get('allows_demo', False), bool):
            raise ValidationError('The demonstration setting must be true or false.')
        seen.add(key)
        result.append({'id': key, 'label': label.strip(), 'allows_demo': item.get('allows_demo', False)})
    return result
