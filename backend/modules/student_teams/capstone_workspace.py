"""Read-only batch/phase navigation shared by adviser files and grade review.

The selected term is an evidence context, never permission to reopen that term.
Legacy consumers opt in with capstone_view so PIT and student APIs retain their
existing contracts.
"""
from rest_framework.exceptions import ValidationError

from academic_period_management.services import active_semester
from defensys_backend.read_projection import read_memoize
from .capstone_context import phase_for, phase_label, phase_requirements
from .capstone_history import history_teams_for, recorded_authority
from .capstone_lifecycle import recorded_team, term_key
from .participation import intake_for


def enabled(request):
    return bool(request.query_params.get('capstone_view')) and request.query_params.get('scope', 'capstone') == 'capstone'


def identity_text(team):
    """Search the displayed identity rather than a team's later mutable name."""
    row = getattr(team, '_recorded_term', None)
    if row:
        values = [row.snapshot.get(key, '') for key in (
            'name', 'project_title', 'leader_name', 'adviser_name', 'adviser_username')]
    else:
        from .serializers import display_name
        values = [team.name, team.project_title, display_name(team.leader),
            display_name(team.adviser), team.adviser.username if team.adviser_id else '']
    return ' '.join(str(value or '') for value in values).casefold()


@read_memoize
def projection(request):
    from authentication_access_control.workspaces import workspace_teams_for
    from .models import TeamTermParticipation

    params, user = request.query_params, request.user
    view = params.get('capstone_view', 'ongoing')
    if view not in ('ongoing', 'history'):
        raise ValidationError({'capstone_view': 'Choose ongoing or history.'})
    workspace = params.get('workspace', '')
    visible = history_teams_for(user, workspace).filter(level__icontains='Capstone')
    live_ids = set(workspace_teams_for(user, workspace).values_list('pk', flat=True))
    active = active_semester()
    teams = list(visible.select_related('semester__school_year', 'intake_semester__school_year', 'leader', 'adviser'))
    rows = list(TeamTermParticipation.objects.filter(team__in=teams).select_related('semester__school_year'))
    by_team = {}
    for row in rows:
        by_team.setdefault(row.team_id, []).append(row)
    # A closed source phase is still part of an ongoing batch. Only ended
    # batches belong in History; assigning an additional batch archives none.
    current_intakes = set()
    for team in teams:
        closed_current = any(r.semester_id == team.semester_id and r.closed_at for r in by_team.get(team.pk, []))
        if active and team.semester_id == active.pk and not closed_current:
            intake = intake_for(team)
            current_intakes.add(str(intake.pk) if intake else 'unassigned')
    batches = {}
    for team in teams:
        intake = intake_for(team)
        key = str(intake.pk) if intake else 'unassigned'
        if (key in current_intakes) != (view == 'ongoing'):
            continue
        batches.setdefault(key, {'intake': intake, 'teams': []})['teams'].append(team)
    choices = sorted(batches, key=lambda k: term_key(batches[k]['intake']) if batches[k]['intake'] else ('', 0), reverse=True)
    requested_batch = params.get('batch_id', '')
    if requested_batch and requested_batch != 'unassigned' and (not requested_batch.isdecimal() or int(requested_batch) < 1):
        raise ValidationError({'batch_id': 'Choose a valid Capstone intake.'})
    selected = requested_batch or (choices[0] if choices else '')
    contexts, groups = {}, {}
    for team in batches.get(selected, {}).get('teams', []):
        term_rows = {r.semester_id: r for r in by_team.get(team.pk, [])}
        terms = {r.semester_id: r.semester for r in term_rows.values() if r.closed_at}
        terms[team.semester_id] = team.semester
        for term_id, term in terms.items():
            row = term_rows.get(term_id)
            if team.pk not in live_ids and not recorded_authority(user, row):
                continue
            context = recorded_team(team, term) if row and row.closed_at else team
            contexts.setdefault(term_id, {})[team.pk] = context
            phase = phase_for(team, term)
            read_only = view == 'history' or not term.is_active or bool(row and row.closed_at)
            group = groups.setdefault(term_id, {'semester_id': term_id, 'phase': phase,
                'phase_label': phase_label(phase), 'display_semester': term.display_name,
                'read_only': True, 'stage_ids': set(), 'stage_entries': {}})
            group['read_only'] = group['read_only'] and read_only
            group['stage_ids'].update(r['id'] for r in phase_requirements(context))
            for requirement in phase_requirements(context):
                group['stage_entries'][requirement['id']] = {
                    'key': f'{term_id}:{requirement["id"]}', 'stage_id': requirement['id'],
                    'stage_label': requirement['label'], 'semester_id': term_id,
                    'display_semester': term.display_name,
                    'phase_label': phase_label(phase), 'order': requirement.get('order', 0)}
    groups = sorted(groups.values(), key=lambda g: term_key(next(iter(contexts[g['semester_id']].values())).semester))
    stage_options = []
    for group in groups:
        group['stage_count'] = len(group.pop('stage_ids'))
        entries = sorted(group.pop('stage_entries').values(), key=lambda r: (r['order'], r['stage_id']))
        stage_options.extend({**entry, 'read_only': group['read_only']} for entry in entries)
    raw_term = params.get('phase_semester_id', '')
    if raw_term and (not raw_term.isdecimal() or int(raw_term) < 1):
        raise ValidationError({'phase_semester_id': 'Choose a valid phase semester.'})
    selected_term = int(raw_term) if raw_term else (
        active.pk if active and active.pk in contexts else (groups[-1]['semester_id'] if groups else None))
    current_phase = next((g for g in groups if active and g['semester_id'] == active.pk), None)
    selected_stage = None
    if params.get('stage_sequence') == 'all':
        key = params.get('stage_key', '')
        if key:
            selected_stage = next((option for option in stage_options if option['key'] == key), None)
            if selected_stage is None or (raw_term and int(raw_term) != selected_stage['semester_id']):
                raise ValidationError({'stage_key': 'Choose a stage in this batch and its recorded semester.'})
        else:
            candidates = [option for option in stage_options if option['semester_id'] == selected_term]
            requested_label = params.get('stage_label', '')
            selected_stage = next((o for o in candidates if o['stage_label'] == requested_label), None)
            if selected_stage is None and requested_label:
                selected_stage = next((o for o in reversed(stage_options) if o['stage_label'] == requested_label), None)
            if selected_stage is None and candidates:
                from repository.deliverables.services import current_stage_for_team
                labels = {current_stage_for_team(t) for t in contexts[selected_term].values()}
                selected_stage = next((o for o in candidates if o['stage_label'] in labels), candidates[0])
            if selected_stage is None and not raw_term and stage_options:
                selected_stage = stage_options[-1]
        if selected_stage:
            selected_term = selected_stage['semester_id']
    selected_contexts = contexts.get(selected_term, {})
    semester = next(iter(selected_contexts.values())).semester if selected_contexts else None
    metadata = {'view': view, 'batch_id': selected, 'phase_semester_id': selected_term,
        'read_only': next((g['read_only'] for g in groups if g['semester_id'] == selected_term), True),
        'batches': [{'value': k, 'label': batches[k]['intake'].display_name if batches[k]['intake'] else 'Intake needs review'} for k in choices],
        'phase_groups': groups, 'stage_options': stage_options,
        'selected_stage_key': selected_stage['key'] if selected_stage else '',
        'selected_stage_label': selected_stage['stage_label'] if selected_stage else '',
        'current_phase': current_phase}
    return {'metadata': metadata, 'contexts': selected_contexts, 'semester': semester,
        'teams': visible.filter(pk__in=selected_contexts), 'contexts_by_semester': contexts}


def grade_queryset(request, queryset):
    """Apply the exact authorized batch and term without mixing score groups."""
    data = projection(request)
    semester = data['semester']
    return queryset.filter(team_id__in=data['contexts'], semester=semester) if semester else queryset.none()
