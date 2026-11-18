"""Section identities and score coverage derived from the assigned rubric."""

import hashlib
import json
from decimal import Decimal, InvalidOperation

from django.core.exceptions import ValidationError


def section_definitions(rubric):
    if rubric is None or rubric.scale != 'Points-Based (Sections)':
        return []
    groups = {}
    for criterion in rubric.criteria.all():
        title = criterion.section.strip()
        target = rubric.target_type if rubric.target_type != 'both' else criterion.target_type
        if title:
            groups.setdefault((title, target), []).append(criterion)
    result = []
    for (title, target), criteria in groups.items():
        ids = sorted(c.pk for c in criteria)
        identity = json.dumps([rubric.pk, target, ids], separators=(',', ':'))
        result.append({
            'section_key': hashlib.sha256(identity.encode()).hexdigest(),
            'name': title, 'target_type': target, 'criterion_ids': ids,
            'max_score': sum(c.max_score for c in criteria),
            'weight': sum((c.weight for c in criteria), Decimal('0')),
            'display_order': min(c.display_order for c in criteria),
            'criteria': [{'id': c.pk, 'name': c.name, 'description': c.description,
                          'max_score': c.max_score} for c in criteria],
        })
    return result


def numeric_score(value, maximum):
    try:
        score = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValidationError('Score must be numeric.') from exc
    if not score.is_finite() or score < 0 or score > maximum:
        raise ValidationError(f'Score must be between 0 and {maximum}.')
    if score != score.quantize(Decimal('0.01')):
        raise ValidationError('Use up to 2 decimal places.')
    return score.quantize(Decimal('0.01'))


def validate_scores(rubric, criteria, scores, sections, *, partial=False):
    """Return actual criterion/section rows; never infer marks for guidance."""
    if not isinstance(scores, list) or not isinstance(sections, list):
        raise ValidationError('criteria_scores and section_scores must be lists.')
    allowed = {c.pk: c for c in criteria}
    definitions = {s['section_key']: s for s in section_definitions(rubric)
                   if set(s['criterion_ids']).issubset(allowed)}
    covered, clean_scores, clean_sections = set(), [], []
    for item in sections:
        if not isinstance(item, dict) or not isinstance(item.get('section_key'), str):
            raise ValidationError('Each section score must identify an assigned section.')
        section = definitions.get(item['section_key'])
        if section is None or covered.intersection(section['criterion_ids']):
            raise ValidationError('Use each assigned section only once for the correct scoring target.')
        score = numeric_score(item.get('score'), Decimal(section['max_score']))
        covered.update(section['criterion_ids'])
        clean_sections.append({'section_key': section['section_key'], 'score': float(score)})
    for item in scores:
        if not isinstance(item, dict):
            raise ValidationError('Each criterion score must be an object.')
        try:
            criterion_id = int(item.get('criterion_id', item.get('id')))
        except (ValueError, TypeError) as exc:
            raise ValidationError('Each score must have a valid criterion ID.') from exc
        if criterion_id not in allowed or criterion_id in covered:
            raise ValidationError('Scores must match the rubric without duplicate or overlapping sources.')
        score = numeric_score(item.get('score'), Decimal(allowed[criterion_id].max_score))
        covered.add(criterion_id)
        clean_scores.append({'criterion_id': criterion_id, 'score': float(score)})
    if not partial and covered != set(allowed):
        raise ValidationError('Score every required criterion or enter its overall section score before submitting.')
    return clean_scores, clean_sections


def section_payload(submission):
    return [{'section_key': row.section_key, 'score': float(row.score),
             'max_score': float(row.max_score_snapshot)} for row in submission.section_scores.all()]


def require_section_client(schedule, payload, **owner):
    """Old clients must not unknowingly replace a newer overall-score draft."""
    from defense.scheduler.models import PanelistEvaluationDraft
    draft = PanelistEvaluationDraft.objects.filter(schedule=schedule, **owner).first()
    incoming = payload.get('submissions', [])
    if not isinstance(incoming, list):
        incoming = []
    has_sections = any(s.get('section_scores') for s in incoming if isinstance(s, dict))
    had_sections = draft and any(s.get('section_scores') for s in draft.submissions)
    if (has_sections or had_sections) and payload.get('section_scoring_version') != 1:
        raise ValidationError('Update or refresh the application before editing an overall section score.')
