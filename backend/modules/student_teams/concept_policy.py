"""Resolve imported assignments and explicit, term/context-scoped concept policies."""
from copy import deepcopy

from django.core.exceptions import ValidationError


def context_key(stage):
    return f'{"pit" if hasattr(stage, "event_name") else "capstone"}:{stage.pk}'


def team_policy_key(team, stage):
    return f'{context_key(stage)}:v{team.project_version}'


def proposal_keys(count):
    return [f'c{i}' for i in range(1, count + 1)]


def supplied_title(team, stage):
    """Read explicit, version/context-bound input, never a selected display title."""
    override = (team.concept_policies or {}).get(team_policy_key(team, stage), {})
    if override.get('mode') == 'assigned' or 'seed_title' in override:
        return (override.get('seed_title', override.get('assigned_title', '')) or '').strip()
    assignment = team.concept_assignment or {}
    if assignment.get('project_version') != team.project_version:
        return ''
    key = assignment.get('context_key')
    if not key:
        first = contexts_for(team).first()
        key = context_key(first) if first else None
    return (assignment.get('seed_title', assignment.get('assigned_title', '')) or '').strip() if key == context_key(stage) else ''


def contexts_for(team):
    if team.is_capstone:
        from defense.stages.models import DefenseStage
        return DefenseStage.objects.filter(concept_config__enabled=True).order_by('display_order', 'pk')
    from defense.scheduler.event_scope import pit_events_for_team
    return pit_events_for_team(team).filter(concept_config__enabled=True).order_by('pk')


def resolve_policy(team, stage, *, current=None, use_round=True, section_assignment=None):
    """Stage setup owns new sets; captured hearings retain their exact policy."""
    config = deepcopy(stage.concept_config or {})
    if use_round:
        if current is None:
            from repository.deliverables.models import ConceptRound
            field = 'pit_event_config' if hasattr(stage, 'event_name') else 'defense_stage'
            current = ConceptRound.objects.filter(team=team, project_version=team.project_version,
                **{field: stage}).order_by('-number', '-pk').first()
        if current:
            if current.policy_snapshot:
                return deepcopy(current.policy_snapshot)
            # Legacy rounds retain exactly the set they already contain.
            return {**config, 'mode': 'proposals', 'required_count': len(current.concepts),
                    'assigned_title': '', 'source': 'existing_round'}
    from repository.section_concepts.services import policy_for
    shared = policy_for(team, stage)
    if shared:
        return shared
    title = supplied_title(team, stage)
    return {**config, 'mode': 'proposals', 'required_count': config.get('required_count', 3),
            'assigned_title': '', 'seed_title': title, 'source': 'supplied' if title else 'stage'}


def validate_override(value, *, team=False):
    if not isinstance(value, dict) or value.get('mode', 'auto') not in ('auto', 'assigned', 'proposals'):
        raise ValidationError('Choose automatic, multiple proposals, or one assigned concept.')
    result = {'mode': value.get('mode', 'auto')}
    if result['mode'] == 'proposals':
        count = value.get('required_count', 3)
        if type(count) is not int or not 1 <= count <= 10:
            raise ValidationError('Require between 1 and 10 concepts.')
        result['required_count'] = count
    if team and result['mode'] == 'assigned':
        title = value.get('assigned_title', '')
        if not isinstance(title, str) or not title.strip() or len(title.strip()) > 255:
            raise ValidationError('Enter an assigned project/module title of up to 255 characters.')
        result['assigned_title'] = title.strip()
    return result


def initial_concepts(policy):
    keys = policy.get('concept_keys') or proposal_keys(policy['required_count'])
    return [{'key': key, 'title': (policy.get('seed_title') or policy.get('assigned_title', '')) if i == 0 else '',
             'decision': '', 'remarks': ''} for i, key in enumerate(keys)]


def title_progress(policy, current=None):
    concepts = current.concepts if current else initial_concepts(policy)
    provided = sum(bool(c.get('title', '').strip()) for c in concepts)
    return {'required_count': len(concepts), 'provided_count': provided,
            'remaining_count': len(concepts) - provided}
