"""Read-only shared-system history from recorded hearings and submission sets.

Never recreate a historical roster from current membership. Configured contexts
with no evidence remain visible, and independent work after departure is excluded.
"""
from django.db.models import Q

from .models import SharedDeliverableSet, SharedModuleRedefenseDecision


def history_payload(project, actor, *, team_id=None):
    from . import services, continuation
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule

    links = list(project.team_links.select_related('team__semester', 'team__adviser'))
    pairs = {(link.team_id, link.project_version) for link in links}
    candidates = [link.team for link in links] + list(continuation.participants(project))
    if team_id is not None:
        candidates = [team for team in candidates if team.pk == team_id]
        if not candidates:
            raise PermissionError('This team has no recorded connection to the shared system.')
    own = [team for team in candidates if team.leader_id == actor.pk or
           team.memberships.filter(student=actor).exists()]
    anchor = next(iter(own or candidates), None)
    catalog = []
    if anchor and not project.pit_event_config_id:
        from student_teams.capstone_lifecycle import requirements_for
        catalog = [{'id': row['id'], 'label': row['label'], 'order': row['order']}
                   for row in requirements_for(anchor)]
    elif anchor:
        from defense.scheduler.event_scope import pit_events_for_team
        catalog = [{'id': event.pk, 'label': event.label, 'order': index}
                   for index, event in enumerate(pit_events_for_team(anchor).order_by('pk'))]
    stages = {row['id']: {**row, 'records': []} for row in catalog}
    context = project.context
    stages.setdefault(context.pk, {'id': context.pk, 'label': context.label,
        'order': getattr(context, 'display_order', 0), 'records': []})
    names = dict(StudentTeam.objects.filter(pk__in={pk for pk, _ in pairs}).values_list('pk', 'name'))

    def roster(rows):
        if rows is None:
            return None
        return [{'id': row.get('team_id', row.get('id')),
                 'project_version': row.get('project_version', row.get('version')),
                 'name': row.get('name') or names.get(row.get('team_id', row.get('id')), 'Team name unavailable')}
                for row in rows]

    def record(stage, value):
        stages.setdefault(stage.pk, {'id': stage.pk, 'label': stage.label,
            'order': getattr(stage, 'display_order', 0), 'records': []})
        teams = value.get('teams')
        value.update(team_count=None if teams is None else len(teams))
        stages[stage.pk]['records'].append(value)

    rounds = project.rounds.prefetch_related('systems', 'module_rounds__team').order_by('number', 'pk')
    for hearing in rounds:
        captured = hearing.decision_snapshot or hearing.endorsement_snapshot
        corrections = hearing.decision_snapshot.get('selection_corrections', [])
        original = corrections[0].get('previous_decision', {}) if corrections else {}
        rows = captured.get('teams') if 'teams' in captured else None
        if not captured and not hearing.verdict:
            rows = list(services.active_links(project).values('team_id', 'project_version'))
        systems = [{'key': row.key, 'title': row.title, 'decision': row.decision,
                    'remarks': row.remarks} for row in hearing.systems.all()]
        from django.utils.dateparse import parse_datetime
        original_date = parse_datetime(original.get('decided_at') or '')
        record(context, {'id': f'hearing-{hearing.pk}', 'kind': 'hearing',
            'attempt': hearing.number, 'outcome': original.get('verdict', hearing.verdict),
            'date': (original_date or hearing.decided_at or hearing.created_at).isoformat(),
            'remarks': original.get('remarks', hearing.remarks),
            'selected_key': original.get('selected_key', hearing.selected_key),
            'systems': original.get('systems', systems),
            'teams': roster(rows), 'roster_basis': 'Recorded roster' if captured else 'Current participants',
            'modules': [{'team_id': module.team_id, 'team_name': module.team.name,
                'attempt': module.number, 'outcome': module.verdict,
                'concepts': [{'key': item.get('key'), 'title': item.get('title'),
                              'decision': item.get('decision')} for item in module.concepts]}
                for module in hearing.module_rounds.all()
                if not corrections and (module.schedule_id or module.verdict)]})
        for index, correction in enumerate(corrections):
            prior = correction.get('previous_decision', {}).get('systems', systems)
            titles = {row['key']: row['title'] for row in prior}
            titles.update({row['key']: row['title'] for row in systems})
            record(context, {'id': f'correction-{hearing.pk}-{index}', 'kind': 'selection_correction',
                'date': correction.get('at', ''), 'teams': None,
                'from_title': titles.get(correction.get('from_key'), 'Earlier system'),
                'to_title': titles.get(correction.get('to_key'), 'Selected system'),
                'remarks': correction.get('reason', ''), 'recorded_by': correction.get('by_name', '')})

    captured = list(SharedDeliverableSet.objects.filter(source_project=project).select_related(
        'defense_stage', 'pit_event_config', 'section__semester').prefetch_related('files').order_by('created_at', 'pk'))
    stage_pairs = {}
    for submission in captured:
        stage = submission.pit_event_config or submission.defense_stage
        stage_pairs.setdefault(stage.pk, set()).update(
            (row['id'], row['version']) for row in submission.team_snapshot)
        record(stage, {'id': f'shared-{submission.pk}', 'kind': 'shared_submission',
            'date': submission.created_at.isoformat(), 'semester': submission.section.semester.display_name,
            'systems': submission.system_snapshot, 'teams': roster(submission.team_snapshot),
            'roster_basis': 'Captured with shared submission',
            'files': [{'name': row.file_name, 'revision': row.revision, 'status': row.status}
                      for row in sorted(submission.files.all(), key=lambda item:
                          (item.deliverable_id, item.slot_key, item.revision, item.pk))]})

    directions = list(SharedModuleRedefenseDecision.objects.filter(
        source_round__section_round__project=project).select_related('source_round__team',
        'source_round__defense_stage', 'decided_by'))
    departures = {}
    for decision in directions:
        source = decision.source_round
        if not source.defense_stage_id:
            continue
        if decision.direction == 'independent':
            departures[(source.team_id, source.project_version)] = decision.decided_at
        record(source.defense_stage, {'id': f'direction-{decision.pk}', 'kind': 'team_direction',
            'date': decision.decided_at.isoformat(), 'direction': decision.direction,
            'team_name': source.team.name, 'teams': None,
            'recorded_by': decision.decided_by.get_full_name() or decision.decided_by.username})

    # Later-stage hearings are included only for team versions captured in this
    # system's shared evidence, before any recorded independent departure.
    schedule_query = Q(pk__in=[])
    for stage_id, members in stage_pairs.items():
        for pk, version in members:
            identity = Q(team_id=pk, project_version=version)
            schedule_query |= identity & (Q(event_name=stages[stage_id]['label']) if project.pit_event_config_id
                                          else Q(defense_stage_id=stage_id))
    schedules = DefenseSchedule.objects.filter(schedule_query,
        scope='pit' if project.pit_event_config_id else 'capstone').select_related(
            'team', 'defense_stage', 'semester').prefetch_related('grade_records', 'attempt_grade_snapshots').order_by('scheduled_date', 'start_time', 'pk')
    for schedule in schedules:
        if schedule.defense_stage_id == project.defense_stage_id and not project.pit_event_config_id:
            continue  # The shared hearing above already owns this concept event.
        left = departures.get((schedule.team_id, schedule.project_version))
        if left and schedule.created_at >= left:
            continue
        stage_id = schedule.defense_stage_id if not project.pit_event_config_id else next(
            (key for key, value in stages.items() if value['label'] == schedule.event_name), None)
        if stage_id not in stages:
            continue
        evidence = next(iter(schedule.grade_records.all()), None) or next(iter(schedule.attempt_grade_snapshots.all()), None)
        stages[stage_id]['records'].append({'id': f'defense-{schedule.pk}', 'kind': 'team_defense',
            'date': schedule.scheduled_date.isoformat(), 'team_name': schedule.team.name,
            'outcome': 'failed' if evidence and evidence.outcome_metadata.get('closure', {}).get('failed')
                else getattr(evidence, 'verdict', ''), 'status': schedule.status,
            'attempt': getattr(evidence, 'attempt_count', getattr(evidence, 'attempt_number', None)),
            'semester': schedule.semester.display_name})

    previous = None
    for stage in sorted(stages.values(), key=lambda row: (row['order'], row['id'])):
        stage['records'].sort(key=lambda row: (row.get('date', ''), row['id']))
        for item in stage['records']:
            if item.get('teams') is None or item.get('roster_basis') == 'Current participants':
                continue
            members = {(row['id'], row['project_version']) for row in item['teams']}
            item['joined_count'] = len(members - previous) if previous is not None else 0
            item['left_count'] = len(previous - members) if previous is not None else 0
            previous = members
    data = {'project_id': project.pk, 'section': project.section.section,
            'stages': sorted(stages.values(), key=lambda row: (row['order'], row['id']))}
    from grading.grades.student_visibility import student_assessment_payload
    return student_assessment_payload(data, actor)
