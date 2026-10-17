"""Public evaluator identities never contain guest access credentials."""
import hashlib
import re

ACCESS_CODE = re.compile(r'\bDEF-[A-Z0-9]+\b', re.IGNORECASE)


def public_evaluation_text(value):
    return ACCESS_CODE.sub('[redacted]', value or '')


def public_guest_name(value):
    return public_evaluation_text(value).strip() or 'External evaluator'


def breakdown_identity(row, legacy_submissions=None):
    """Use the source record, with a safe fallback for pre-source-link breakdowns."""
    header, _, comment = (row.remarks or '').partition('\n')
    header = header.strip()
    submission = row.source_submission if row.source_submission_id else (legacy_submissions or {}).get(header)
    key, name = None, None
    if row.evaluation_type == 'panel':
        if submission and submission.guest_code_id:
            key, name = f'guest:{submission.guest_code_id}', public_guest_name(submission.guest_name)
        elif submission and submission.panelist_id:
            key = submission.panelist.username
            name = submission.panelist.get_full_name() or key
        elif header.startswith('Guest panelist:'):
            # The legacy suffix is an access credential, including old custom formats.
            label = header.removeprefix('Guest panelist:').strip()
            name = public_guest_name(re.sub(r'\s+\([^()]*\)$', '', label))
            key = 'legacy-guest:' + hashlib.sha256(header.encode()).hexdigest()[:24]
        elif header.startswith('Panelist:'):
            key = header.removeprefix('Panelist:').strip()
            name = f'Panelist {key}'
        else:
            key = 'legacy-panel:' + hashlib.sha256(header.encode()).hexdigest()[:24]
            name = 'Panelist'
        if header.startswith(('Panelist:', 'Guest panelist:')):
            remarks = comment
        else:
            remarks = row.remarks
    else:
        remarks = row.remarks
    return {'panelist_key': key, 'evaluator_name': name, 'remarks': public_evaluation_text(remarks)}
