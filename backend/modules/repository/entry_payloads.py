"""Shared dict fields for repository list/search payloads (vault + audit)."""

ML_FIELD_NAMES = (
    'extracted_text',
    'topics',
    'summary',
    'category',
    'category_confidence',
)


def ml_fields_from(obj):
    return {
        'extracted_text': getattr(obj, 'extracted_text', None) or '',
        'topics': getattr(obj, 'topics', None) or [],
        'summary': getattr(obj, 'summary', None) or '',
        'category': getattr(obj, 'category', None) or '',
        'category_confidence': getattr(obj, 'category_confidence', None),
    }


def empty_ml_fields():
    return {
        'extracted_text': '',
        'topics': [],
        'summary': '',
        'category': '',
        'category_confidence': None,
    }


def apply_list_entry_options(entry, *, include_ml=False, include_audit_trail=False):
    """Strip heavy fields from audit list rows unless explicitly requested."""
    if not include_ml:
        for name in ML_FIELD_NAMES:
            if name in entry:
                if name == 'topics':
                    entry[name] = []
                elif name == 'category_confidence':
                    entry[name] = None
                else:
                    entry[name] = ''
    if not include_audit_trail and 'audit_trail' in entry:
        entry['audit_trail'] = []
