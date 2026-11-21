"""Documenter drafts stay unofficial until the reviewed minutes are submitted."""
from copy import deepcopy
import uuid

from django.core.exceptions import ValidationError

from grading.grades.deliberation import _entries, _text, confirm, decision_payload, source_for
from grading.grades.outcome_rules import documenter_policy, outcome_payload, policy_for


def grade_for(minutes):
    from grading.grades.models import TeamGrade
    return TeamGrade.objects.filter(schedule_id=minutes.schedule_id).select_related('schedule').first()


def validate_draft(value):
    allowed = {'request_id', 'review_token', 'verdict', 'selected_key', 'reason', 'instructions',
               'revision_entries', 'demo_requirements', 're_demo_required'}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ValidationError('Submit a valid panel-decision draft.')
    if value == {}:
        return {}
    result = deepcopy(value)
    try:
        uuid.UUID(str(result.get('request_id')))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ValidationError('Provide the decision draft identity.') from exc
    for key, maximum in [('review_token', 128), ('selected_key', 128), ('reason', 2000), ('instructions', 5000)]:
        result[key] = _text(result.get(key, ''), key, maximum)
    if result.get('verdict', '') not in ('', 'approved', 'approved_with_revisions', 'for_redefense'):
        raise ValidationError('Choose a valid panel verdict.')
    if not isinstance(result.get('re_demo_required', False), bool):
        raise ValidationError('The re-demo setting must be true or false.')
    for key, maximum, fields in [('revision_entries', 12, {'area_id', 'label', 'severity'}),
                                  ('demo_requirements', 40, {'area_id', 'text'})]:
        rows = result.get(key, [])
        if not isinstance(rows, list) or len(rows) > maximum:
            raise ValidationError(f'Record up to {maximum} {key.replace("_", " ")}.')
        for row in rows:
            if not isinstance(row, dict) or set(row) - fields:
                raise ValidationError('The decision draft contains unsupported fields.')
            for field, text in row.items():
                _text(text, field, {'label': 80, 'text': 1000, 'area_id': 64, 'severity': 10}[field])
            if key == 'revision_entries' and row.get('severity', '') not in ('', 'minor', 'major'):
                raise ValidationError('Choose Minor or Major revision.')
    return result


def draft_payload(minutes):
    grade = grade_for(minutes)
    data = minutes.decision_draft
    if not grade or not data:
        return None
    try:
        entries, tasks = _entries(policy_for(minutes.schedule), data, data.get('verdict'))
    except ValidationError:
        return None
    rule = outcome_payload(grade)
    if not rule or data.get('verdict') not in rule['allowed_verdicts']:
        return None
    if data.get('verdict') == 'for_redefense' and rule['outcome'] == 'approved' and (
            not data.get('reason', '').strip() or not data.get('instructions', '').strip()):
        return None
    selected = data.get('selected_key', '')
    qualifiers = [row for row in rule['assessments'] if row['qualifies']]
    if rule['per_concept'] and data['verdict'] != 'for_redefense':
        selected = selected or (qualifiers[0]['key'] if len(qualifiers) == 1 else '')
        if selected not in [row['key'] for row in qualifiers]:
            return None
    return {'verdict': data['verdict'], 'revision_entries': entries,
        'selected_title': next((row['title'] for row in qualifiers if row['key'] == selected), ''),
        'selected_key': selected, 'reason': data.get('reason', ''), 'instructions': data.get('instructions', ''),
        'demo_requirements': [{key: value for key, value in row.items() if key != 'id'} for row in tasks],
        're_demo_required': bool(tasks), 'recording_method': 'documenter_minutes'}


def context(minutes):
    if not documenter_policy(minutes.schedule):
        return None
    grade = grade_for(minutes)
    official = source_for(minutes.schedule)
    return {'grade_id': grade.pk if grade else None,
        'grade_updated_at': grade.updated_at.isoformat() if grade else None,
        'outcome_rule': outcome_payload(grade) if grade else None,
        'can_request_correction': bool(official and grade and grade.schedule_id == minutes.schedule_id
            and not grade.closed_as_failed and minutes.schedule.status != 'archived'
            and not grade.corrections.filter(status='pending', changes__has_key='panel_decision').exists()),
        'draft': minutes.decision_draft, 'draft_ready': draft_payload(minutes) is not None}


def record_on_submission(minutes, actor, supplied_token):
    from .outcome import review_token
    if not supplied_token or supplied_token != review_token(minutes):
        raise ValidationError('The minutes or decision draft changed. Review the current PDF before submitting.')
    if not draft_payload(minutes):
        raise ValidationError('Complete the panel-decision draft and required panel evaluations before submitting.')
    grade = grade_for(minutes)
    outcome = confirm(grade, actor=actor, data=minutes.decision_draft, minutes=minutes)
    minutes.outcome_snapshot = decision_payload(outcome, public=True)

