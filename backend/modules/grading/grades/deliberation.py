"""Chair-issued panel decisions with immutable attempt identity and honest scores."""
import hashlib
import json
import uuid

from django.core.exceptions import ValidationError
from django.db import transaction

from .outcome_models import DefenseOutcome
from .outcome_rules import deliberation_policy, outcome_payload, policy_for, hearing_concepts, concept_keys


def source_for(schedule):
    if not schedule or not deliberation_policy(schedule):
        return None
    return DefenseOutcome.objects.filter(schedule_id=schedule.pk).select_related('confirmed_by').first()


def decision_payload(outcome, *, public=False):
    if outcome is None:
        return None
    result = {'id': outcome.pk, 'schedule_id': outcome.schedule_id, 'revision': outcome.revision,
        'verdict': outcome.verdict, 'selected_key': outcome.selected_key,
        'selected_title': next((row.get('title', '') for row in outcome.assessment_snapshot.get('assessments', [])
                                if row['key'] == outcome.selected_key), '') if outcome.selected_key else '',
        'reason': outcome.reason, 'instructions': outcome.instructions,
        'revision_entries': outcome.revision_entries, 'demo_requirements': outcome.demo_requirements,
        're_demo_required': outcome.re_demo_required,
        'confirmed_at': outcome.confirmed_at.isoformat()}
    if not public:
        result.update(confirmed_by=outcome.confirmed_by_id,
            confirmed_by_name=outcome.confirmed_by.get_full_name() or outcome.confirmed_by.username,
            decision_source=outcome.decision_source)
    return result


def version_payload(outcome, revision, *, public=False):
    if outcome.revision == revision:
        return decision_payload(outcome, public=public)
    previous = next((row for row in outcome.history if row.get('revision') == revision), None)
    if previous is None:
        return None
    allowed = set(decision_payload(outcome, public=public))
    return {key: value for key, value in previous.items() if key in allowed}


def payload(grade, actor=None):
    if not deliberation_policy(grade.schedule):
        return None
    from .defense_workflow import is_chair
    from defense.scheduler.panelist_evaluation import assessment_unavailable_reason
    official = source_for(grade.schedule)
    rule = outcome_payload(grade)
    reason = assessment_unavailable_reason(grade.schedule, grade)
    return {'enabled': True, 'revision_areas': policy_for(grade.schedule)['revision_areas'],
        'decision': decision_payload(official),
        'can_request_correction': bool(official and actor and is_chair(grade, actor)
            and not grade.closed_as_failed and grade.schedule.status != 'archived'
            and not grade.corrections.filter(status='pending', changes__has_key='panel_decision').exists()),
        'can_confirm': bool(actor and is_chair(grade, actor) and not official and not grade.verdict
                            and not reason and rule and rule['allowed_verdicts']),
        'unavailable_reason': reason,
        'requires_chair_confirmation': official is None}


def _text(value, label, maximum=5000):
    if not isinstance(value, str) or len(value) > maximum:
        raise ValidationError(f'{label} must be text of up to {maximum} characters.')
    return value.strip()


def _entries(policy, data, verdict):
    areas = {area['id']: area for area in policy['revision_areas']}
    entries = data.get('revision_entries', [])
    if not isinstance(entries, list) or len(entries) > len(areas):
        raise ValidationError('Record each applicable revision area once.')
    result, seen = [], set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) - {'area_id', 'severity'}:
            raise ValidationError('Choose a revision requirement for each configured area.')
        key, severity = entry.get('area_id'), entry.get('severity')
        if not isinstance(key, str) or key not in areas or key in seen or severity not in ('none', 'minor', 'major'):
            raise ValidationError('Use unique configured revision areas and valid revision levels.')
        seen.add(key)
        result.append({**areas[key], 'area_id': key, 'severity': severity})
    result.sort(key=lambda entry: list(areas).index(entry['area_id']))
    if verdict != 'for_redefense' and seen != set(areas):
        raise ValidationError('Record every revision area; unanswered does not mean No revision.')
    if verdict == 'approved' and any(entry['severity'] != 'none' for entry in result):
        raise ValidationError('Use Approved with revisions when corrections are required.')
    if verdict == 'approved_with_revisions' and not any(entry['severity'] != 'none' for entry in result):
        raise ValidationError('Record at least one minor or major revision.')
    requirements = data.get('demo_requirements', [])
    if not isinstance(requirements, list) or len(requirements) > 40:
        raise ValidationError('Record up to 40 required demonstrations.')
    by_area = {entry['area_id']: entry for entry in result}
    demonstrations = []
    for item in requirements:
        if not isinstance(item, dict) or set(item) - {'area_id', 'text'}:
            raise ValidationError('Each demonstration needs a revision area and requirement text.')
        key = item.get('area_id')
        if not isinstance(key, str):
            raise ValidationError('Choose a configured revision area for each demonstration.')
        area = by_area.get(key, {})
        if not area.get('allows_demo') or area.get('severity') not in ('minor', 'major'):
            raise ValidationError('Demonstrations must belong to an eligible area requiring revision.')
        text = _text(item.get('text'), 'Demonstration requirement', 1000)
        if not text:
            raise ValidationError('Describe every required demonstration.')
        if any(row['area_id'] == key and row['text'] == text for row in demonstrations):
            raise ValidationError('Record each requested demonstration once.')
        demonstrations.append({'id': str(uuid.uuid4()), 'area_id': key, 'text': text})
    requested = data.get('re_demo_required', False)
    if not isinstance(requested, bool) or requested != bool(demonstrations):
        raise ValidationError('Re-demo requires an explicit, nonempty list of demonstrations.')
    if demonstrations and verdict != 'approved_with_revisions':
        raise ValidationError('Re-demo is a follow-up under Approved with revisions.')
    return result, demonstrations


@transaction.atomic
def confirm(grade, *, actor, data):
    from .automatic_outcomes import _locked_grade
    from .defense_workflow import is_chair, require_current, _record_outcome
    if not deliberation_policy(grade.schedule):
        raise ValidationError('This hearing retains its captured outcome policy.')
    grade = _locked_grade(grade)
    if not is_chair(grade, actor):
        raise PermissionError('Only the assigned panel chair can confirm the panel decision.')
    allowed_fields = {'request_id', 'review_token', 'verdict', 'selected_key', 'reason', 'instructions',
                      'revision_entries', 'demo_requirements', 're_demo_required'}
    if not isinstance(data, dict) or set(data) - allowed_fields:
        raise ValidationError('Unsupported panel decision fields.')
    try:
        request_id = uuid.UUID(str(data.get('request_id')))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ValidationError('Provide a valid decision request identity.') from exc
    digest = hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()
    previous = DefenseOutcome.objects.filter(request_id=request_id).first()
    if previous:
        if previous.schedule_id != grade.schedule_id or previous.confirmed_by_id != actor.pk or previous.request_digest != digest:
            raise ValidationError('This request identity belongs to a different panel decision.')
        return previous
    require_current(grade)
    if grade.verdict or DefenseOutcome.objects.filter(schedule_id=grade.schedule_id).exists():
        raise ValidationError('The official outcome is already recorded. Use the correction process.')
    rule = outcome_payload(grade)
    if not rule or data.get('review_token') != rule['review_token']:
        raise ValidationError('The assessment changed. Refresh before confirming the decision.')
    verdict = data.get('verdict')
    if verdict not in rule['allowed_verdicts']:
        raise ValidationError(rule['reason'] or 'Complete the required panel assessment and follow its qualifying rules.')
    reason = _text(data.get('reason', ''), 'Decision reason', 2000)
    instructions = _text(data.get('instructions', ''), 'Panel instructions')
    panel_directed = verdict == 'for_redefense' and rule['outcome'] == 'approved'
    if panel_directed and not reason:
        raise ValidationError('Record why the panel requires re-defense despite the qualifying assessment.')
    if panel_directed and not instructions:
        raise ValidationError('Record the required next action for the re-defense.')
    entries, demonstrations = _entries(policy_for(grade.schedule), data, verdict)
    key = data.get('selected_key') or ''
    decisions = None
    replacement = False
    if rule['per_concept']:
        from repository.deliverables.models import ConceptRound
        hearing = ConceptRound.objects.select_related('section_round').get(schedule_id=grade.schedule_id)
        section = hearing.section_round if hearing.section_round_id else None
        candidates = [row['key'] for row in rule['assessments'] if row['qualifies']
                      and (not section or row['key'] == section.selected_key)]
        if verdict in ('approved', 'approved_with_revisions'):
            key = key or (candidates[0] if len(candidates) == 1 else '')
            if key not in candidates:
                raise ValidationError('Select one qualifying concept with the panel decision.')
        elif key:
            raise ValidationError('Re-defense does not award an official approved concept.')
        replacement = bool(section and section.verdict == 'for_redefense')
        required = set(concept_keys(grade.schedule))
        decisions = [{'key': concept['key'], 'decision': verdict if concept['key'] == key else
            'revise' if verdict == 'for_redefense' and (replacement or concept['key'] in required) else 'not_selected',
            'remarks': instructions, 'next_action': ('replace' if replacement else 'revise')
            if verdict == 'for_redefense' and (replacement or concept['key'] in required) else 'omit'}
            for concept in hearing_concepts(grade.schedule)]
    elif key:
        raise ValidationError('This hearing does not select an official concept.')
    result = _record_outcome(grade, actor=actor, verdict=verdict, remarks=instructions or reason,
        concept_decisions=decisions, replacement_concepts_required=replacement, panel_decision=True)
    outcome = DefenseOutcome.objects.create(schedule_id=result.schedule_id, grade=result,
        project_version=result.project_version, verdict=verdict,
        decision_source=(('shared_system' if rule['reason'] else 'cutoff_required')
                         if rule['outcome'] == 'for_redefense' else 'panel_deliberation'),
        selected_key=key, reason=reason or (rule['reason'] if rule['outcome'] == 'for_redefense' else ''),
        instructions=instructions, revision_entries=entries, demo_requirements=demonstrations,
        assessment_snapshot={**rule, 'student_ids': list(result.student_grades.values_list('student_id', flat=True))},
        confirmed_by=actor, request_id=request_id, request_digest=digest)
    from .models import TeamGrade
    TeamGrade.objects.filter(pk=result.pk).update(outcome_metadata={**result.outcome_metadata,
        'official_outcome_id': outcome.pk, 'official_outcome_revision': outcome.revision})
    from .defense_workflow import audit
    audit(result, actor, 'defense.panel_decision_confirmed', decision=decision_payload(outcome),
          assessment_review_token=rule['review_token'])
    from .automatic_outcomes import notify_assessment
    transaction.on_commit(lambda: notify_assessment(result))
    return outcome
