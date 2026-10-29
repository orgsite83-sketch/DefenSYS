"""Read-only concept decisions and a title-only PIT roster handoff.

Never call the deliverable payload/round initializers from a report. Persisted
concept decisions, rather than file acceptance or a team's status, are evidence.
"""
from collections import Counter, defaultdict

from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import PermissionDenied, ValidationError

from authentication_access_control.scopes import is_pit_lead_only
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from repository.deliverables.models import ConceptRound
from student_teams.models import StudentTeam
from student_teams.team_levels import YEAR_LEVEL_CHOICES


STATUS_LABELS = {
    'awaiting_decision': 'Awaiting decision', 'approved': 'Approved',
    'approved_with_revisions': 'Approved with revisions', 'rejected': 'Rejected',
    'not_selected': 'Not selected', 'revise': 'Revision required',
    'for_redefense': 'Re-defense required', 'replacement_required': 'Replacement required',
    'not_submitted': 'No concept submitted', 'not_configured': 'Concepts not configured',
    'failed': 'Failed (stage closure)',
}


def concept_teams(request):
    from reports.catalog_reports import require_manager, period
    require_manager(request)
    teams = StudentTeam.objects.select_related('semester__school_year', 'leader').prefetch_related('memberships__student')
    # This is a management report. Independent adviser visibility never widens
    # a Lead's reporting/export scope.
    if is_pit_lead_only(request.user):
        if request.query_params.get('scope') not in (None, '', 'pit') or request.query_params.get('year_level') not in (None, '', request.user.pit_lead_year):
            raise PermissionDenied('Export only your assigned PIT year.')
        teams = teams.filter(level__icontains='PIT', year_level=request.user.pit_lead_year).exclude(year_level='3rd Year', semester__label='2nd Semester')
    selected = period(request)
    if selected:
        from student_teams.capstone_lifecycle import teams_in_recorded_term
        teams = teams_in_recorded_term(teams, selected)
    scope = request.query_params.get('scope', '')
    if scope not in ('', 'pit', 'capstone'):
        raise ValidationError({'scope': 'Choose PIT or Capstone.'})
    if scope:
        teams = teams.filter(level__icontains=scope)
    year = request.query_params.get('year_level', '')
    if year and year not in YEAR_LEVEL_CHOICES:
        raise ValidationError({'year_level': 'Choose a valid year.'})
    if (scope == 'pit' and year == '4th Year') or (scope == 'capstone' and year in ('1st Year', '2nd Year')):
        raise ValidationError('The year is incompatible with the selected academic scope.')
    for field in ('year_level', 'section'):
        if request.query_params.get(field):
            if selected:
                from student_teams.capstone_lifecycle import filter_recorded_team_field
                teams = filter_recorded_team_field(teams, selected, field, request.query_params[field])
            else:
                teams = teams.filter(**{field: request.query_params[field]})
    return teams.order_by('semester_id', 'section', 'name', 'pk')


def selected_context(request, teams):
    event_id, stage_id = (request.query_params.get(k) for k in ('pit_event_config_id', 'stage_id'))
    if event_id and stage_id:
        raise ValidationError('Choose one PIT event or one Capstone stage.')
    context = None
    if event_id:
        if not event_id.isdigit():
            raise ValidationError({'pit_event_config_id': 'Choose a valid PIT event.'})
        from defense.scheduler.event_scope import pit_events_for_user
        context = get_object_or_404(pit_events_for_user(request.user), pk=event_id)
        if request.query_params.get('scope') == 'capstone':
            raise ValidationError('A PIT event cannot be used for Capstone.')
        if request.query_params.get('semester_id') and str(context.semester_id) != request.query_params['semester_id']:
            raise ValidationError('The PIT event belongs to another academic period.')
        if request.query_params.get('year_level') and context.year_level != request.query_params['year_level']:
            raise ValidationError('The PIT event belongs to another year.')
        teams = teams.filter(level__icontains='PIT', semester_id=context.semester_id, year_level=context.year_level)
        teams = teams.filter(Q(current_defense_stage='') | Q(current_defense_stage__isnull=True)
            | Q(current_defense_stage=context.event_name) | Q(concept_rounds__pit_event_config=context)
            | Q(defense_schedules__event_name=context.event_name, defense_schedules__scope='pit')).distinct()
    elif stage_id:
        if is_pit_lead_only(request.user):
            raise PermissionDenied('Capstone concept reports are available to Admin.')
        if not stage_id.isdigit():
            raise ValidationError({'stage_id': 'Choose a valid Capstone stage.'})
        context = get_object_or_404(DefenseStage, pk=stage_id)
        if request.query_params.get('scope') == 'pit':
            raise ValidationError('A Capstone stage cannot be used for PIT.')
        teams = teams.filter(level__icontains='Capstone')
    return context, teams


def context_key(item):
    return (item.team_id, item.project_version, item.defense_stage_id, item.pit_event_config_id)


def decision_row(team, current, concept, grade, *, latest):
    if grade and team.is_capstone:
        from student_teams.capstone_lifecycle import recorded_team
        team = recorded_team(team, grade.semester)
    decision = concept.get('decision') or 'awaiting_decision'
    if current.replacement_required or current.verdict == 'project_rejected':
        decision = 'replacement_required'
    elif current.verdict == 'for_redefense':
        decision = 'for_redefense'
    if grade and grade.closed_as_failed and grade.schedule_id == current.schedule_id:
        decision = 'failed'
    cleared = bool(grade and grade.revisions_cleared_at and grade.schedule_id == current.schedule_id
        and grade.verdict == current.verdict and grade.revisions_cleared_at >= current.created_at)
    approved = current.verdict == 'approved' or (current.verdict == 'approved_with_revisions' and cleared)
    eligible = bool(latest and current.project_version == team.project_version and approved and not current.replacement_required
        and concept.get('decision') in ('approved', 'approved_with_revisions') and str(concept.get('title') or '').strip())
    shared = current.section_round
    system_title = ''
    if shared:
        system = next((s for s in shared.systems.all() if s.key == concept.get('key')), None)
        system_title = system.title if system else ''
        eligible = bool(eligible and shared.selected_key == concept.get('key') and system
            and system.decision in ('approved', 'approved_with_revisions') and
            (shared.verdict == 'approved' or (shared.verdict == 'approved_with_revisions' and shared.revisions_cleared_at)))
    event = current.pit_event_config
    return {
        'team_id': team.pk, 'team': team.name, 'title': concept.get('title', ''), 'system_title': system_title,
        'scope': 'Capstone' if team.is_capstone else 'PIT', 'year_level': team.year_level, 'section': team.section,
        'period': team.semester.display_name, 'semester_id': team.semester_id,
        'context': event.event_name if event else current.defense_stage.label,
        'pit_event_config_id': current.pit_event_config_id, 'stage_id': current.defense_stage_id,
        'round_id': current.pk, 'round': current.number, 'project_version': current.project_version,
        'concept_key': concept.get('key', ''), 'concept_status': decision,
        'status': STATUS_LABELS.get(decision, decision.replace('_', ' ').title()),
        'revisions': ('Cleared' if cleared else 'Outstanding') if current.verdict == 'approved_with_revisions' else
            ('Shared system revisions outstanding' if shared and shared.verdict == 'approved_with_revisions' and not shared.revisions_cleared_at else ''),
        'eligible_title': eligible, 'current': latest and current.project_version == team.project_version,
    }


def concept_projects(request):
    from reports.catalog_reports import column, dataset, period
    teams = concept_teams(request)
    context, teams = selected_context(request, teams)
    layout = request.query_params.get('layout', 'register') or 'register'
    if layout not in ('register', 'roster'):
        raise ValidationError({'layout': 'Choose Register or Roster template.'})
    history = request.query_params.get('include_history', '0')
    if history not in ('0', '1', 'false', 'true', ''):
        raise ValidationError({'include_history': 'Choose current rounds or include history.'})
    status = request.query_params.get('concept_status', '')
    if status and status not in STATUS_LABELS:
        raise ValidationError({'concept_status': 'Choose a valid concept decision.'})
    if layout == 'roster':
        from reports.catalog_reports import period
        source = period(request, default_active=False)
        if not source or source.label != '1st Semester' or not isinstance(context, PitEventGradingConfig) or context.year_level != '3rd Year' or context.semester_id != source.pk:
            raise ValidationError({'layout': 'Select an explicit 3rd Year, 1st Semester PIT source period and concept event.'})
        if request.query_params.get('scope') not in ('', None, 'pit') or request.query_params.get('year_level') not in ('', None, '3rd Year'):
            raise ValidationError('The roster template requires a 3rd Year PIT source.')
        if not (context.concept_config or {}).get('enabled'):
            raise ValidationError('Select a PIT event with concepts enabled.')
        if status or history in ('1', 'true'):
            raise ValidationError('The roster includes all source teams and only current eligible titles. Clear the decision/history filters.')
    selected_period = period(request)
    from student_teams.capstone_lifecycle import recorded_team
    teams = [recorded_team(team, selected_period) if selected_period else team for team in teams]
    rounds = ConceptRound.objects.filter(team__in=teams).select_related('defense_stage', 'pit_event_config', 'section_round', 'schedule__semester').prefetch_related('section_round__systems').order_by('-number', '-pk')
    if context:
        rounds = rounds.filter(**{('pit_event_config' if isinstance(context, PitEventGradingConfig) else 'defense_stage'): context})
    if selected_period:
        rounds = rounds.filter(Q(schedule__semester=selected_period) | Q(schedule__isnull=True))
    grades = {(context_key(g), g.semester_id): g for g in TeamGrade.all_objects.filter(team__in=teams).order_by('pk')}
    by_team, seen = defaultdict(list), set()
    for current in rounds:
        key = context_key(current)
        latest = key not in seen
        seen.add(key)
        by_team[current.team_id].append((current, latest))
    rows, roster, source_teams = [], [], []
    search = request.query_params.get('search', '').strip().casefold()
    for team in teams:
        team_rows = []
        for current, latest in by_team[team.pk]:
            if history not in ('1', 'true') and (not latest or current.project_version != team.project_version):
                continue
            for concept in current.concepts:
                source_term_id = current.schedule.semester_id if current.schedule_id else selected_period.pk if selected_period else team.semester_id
                team_rows.append(decision_row(team, current, concept, grades.get((context_key(current), source_term_id)), latest=latest))
        if not team_rows:
            from student_teams.concept_policy import contexts_for
            configured = bool((context.concept_config or {}).get('enabled')) if context else contexts_for(team).exists()
            state = 'not_submitted' if configured else 'not_configured'
            assignment = team.concept_assignment or {}
            selected_key = f'{"pit" if isinstance(context, PitEventGradingConfig) else "capstone"}:{context.pk}' if context else None
            assigned_title = assignment.get('assigned_title', '') if (assignment.get('mode') == 'assigned'
                and assignment.get('project_version') == team.project_version
                and (not selected_key or assignment.get('context_key') == selected_key)) else ''
            team_rows.append({'team_id': team.pk, 'team': team.name, 'title': assigned_title, 'scope': 'Capstone' if team.is_capstone else 'PIT',
                'year_level': team.year_level, 'section': team.section, 'period': team.semester.display_name,
                'context': (getattr(context, 'event_name', None) or getattr(context, 'label', 'No recorded concept round')),
                'status': STATUS_LABELS[state], 'concept_status': state, 'eligible_title': False, 'current': True})
        if search and not any(search in str(r.get(field, '')).casefold() for r in team_rows for field in ('title', 'team', 'section', 'system_title')):
            continue
        rows.extend(r for r in team_rows if (not status or r['concept_status'] == status)
            and (not search or any(search in str(r.get(field, '')).casefold() for field in ('title', 'team', 'section', 'system_title'))))
        if layout != 'roster':
            continue
        approved = [r['title'] for r in team_rows if r['eligible_title']]
        if len(approved) > 1:
            raise ValidationError(f'{team.name} has conflicting approved titles. Resolve its concept decisions before exporting.')
        members = {m.student_id: m.student for m in team.memberships.all()}
        if team.leader_id not in members or not team.section or not members:
            raise ValidationError(f'{team.name} needs a valid section, leader and membership roster before export.')
        ordered = [members.pop(team.leader_id), *members.values()]
        source_teams.extend(s.pk for s in ordered)
        for index, student in enumerate(ordered):
            roster.append({'team': team.name if index == 0 else '', 'title': approved[0] if approved and index == 0 else '',
                'section': team.section if index == 0 else '', 'adviser': '', 'members': student.username})
    if layout == 'roster':
        if any(count > 1 for count in Counter(source_teams).values()):
            raise ValidationError('A student belongs to multiple source teams. Resolve duplicate memberships before exporting.')
        names = [r['team'].casefold() for r in roster if r['team']]
        if len(names) != len(set(names)):
            raise ValidationError('Duplicate source team names would merge in the importer. Resolve them before exporting.')
        return dataset('PIT Approved Title Roster', [column('team', 'Team Name'), column('title', 'Capstone Project', 48),
            column('section', 'Section'), column('adviser', 'Adviser'), column('members', 'Team Members')], roster,
            excel_only=True, notes='Admin: keep or clear each title, assign Capstone advisers and review enrollment before importing. Every team needs fresh Capstone files, adviser review and approval. PIT history remains separate.')
    return dataset('Concept Project Register', [column('title', 'Concept / Module Title', 40), column('team', 'Team'),
        column('scope', 'Scope', 14), column('year_level', 'Year', 16), column('section', 'Section', 18),
        column('period', 'Academic Period', 32), column('context', 'Event / Stage', 28), column('status', 'Concept Decision', 28),
        column('revisions', 'Revisions', 18), column('system_title', 'Shared System', 36),
        column('project_version', 'Project Version', 18), column('round', 'Round', 12), column('current', 'Current Round', 18)], rows)
