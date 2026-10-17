"""Resolve imported assignments and explicit, term/context-scoped concept policies."""
from copy import deepcopy

from django.core.exceptions import ValidationError


def context_key(stage):
    return f'{"pit" if hasattr(stage, "event_name") else "capstone"}:{stage.pk}'


def team_policy_key(team, stage):
    return f'{context_key(stage)}:v{team.project_version}'


def contexts_for(team):
    if team.is_capstone:
        from defense.stages.models import DefenseStage
        return DefenseStage.objects.filter(concept_config__enabled=True).order_by('display_order', 'pk')
    from defense.scheduler.event_scope import pit_events_for_team
    return pit_events_for_team(team).filter(concept_config__enabled=True).order_by('pk')


def resolve_policy(team, stage, *, current=None, use_round=True, section_assignment=None):
    """Never infer assignment from a display title; existing hearings own their policy."""
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
    if section_assignment is None:
        from .models import SectionAssignment
        section_assignment = SectionAssignment.objects.filter(semester_id=team.semester_id,
            section=team.section, year_level=team.year_level).first()
    section = (section_assignment.concept_policies or {}).get(context_key(stage), {}) if section_assignment else {}
    override = (team.concept_policies or {}).get(team_policy_key(team, stage), {})
    selected, source = next(((p, s) for p, s in ((override, 'team'), (section, 'section'))
                             if p.get('mode') in ('assigned', 'proposals')), ({}, 'stage'))
    assignment = team.concept_assignment or {}
    if assignment.get('project_version') != team.project_version:
        assignment = {}
    assignment_context = assignment.get('context_key')
    if assignment and not assignment_context:
        first_context = contexts_for(team).first()
        assignment_context = context_key(first_context) if first_context else None
    if not selected and assignment and assignment_context == context_key(stage):
        selected, source = assignment, 'import'
    mode = selected.get('mode', 'proposals')
    title = (selected.get('assigned_title') or assignment.get('assigned_title') or '').strip() if mode == 'assigned' else ''
    return {**config, 'mode': mode, 'required_count': 1 if mode == 'assigned' else selected.get(
        'required_count', config.get('required_count', 3)), 'assigned_title': title, 'source': source}


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
    return [{'key': f'c{i}', 'title': policy.get('assigned_title', '') if i == 1 else '',
             'decision': '', 'remarks': ''} for i in range(1, policy['required_count'] + 1)]
