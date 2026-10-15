"""Stage upload overrides shared by the access dialog and upload enforcement."""
from django.core.exceptions import ValidationError
from django.db import transaction

from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from student_teams.models import StudentTeam
from student_teams.team_levels import normalize_year_level


def manually_locked(team, stage_label, deliverable_type):
    keys = set(team.unlocked_stages or [])
    return f'{stage_label}:{deliverable_type}:locked' in keys or f'{stage_label}:all:locked' in keys


def deliverable_override(team, stage_label, deliverable_id):
    if not deliverable_id:
        return None
    keys = set(team.unlocked_stages or [])
    key = f'{stage_label}:deliverable:{deliverable_id}'
    if f'{key}:locked' in keys:
        return False
    return True if key in keys else None


def _stage_teams(teams, stage, program_scope):
    if program_scope != 'pit':
        return teams
    from defense.scheduler.models import PitEventGradingConfig
    return [team for team in teams if PitEventGradingConfig.objects.filter(
        semester=team.semester, year_level=team.year_level, event_name=stage,
    ).exists()]


def _scope(user, *, scope='global', team=None, program_scope='capstone', year_level=None):
    from academic_period_management.services import active_semester
    is_admin = user.role == 'admin' or user.is_superuser
    is_pit_lead = bool(getattr(user, 'is_pit_lead', False))
    if scope not in {'team', 'global'} or program_scope not in {'capstone', 'pit'}:
        raise ValidationError('Invalid stage access scope.')
    if scope == 'team' and team is None:
        raise ValidationError('A team is required for team access.')
    if team:
        program_scope = 'pit' if team.is_pit else 'capstone'
    if not is_admin:
        if not is_pit_lead or program_scope != 'pit':
            raise PermissionError('Only an Admin or the assigned PIT Lead can manage stage access.')
        assigned_year = normalize_year_level(getattr(user, 'pit_lead_year', '') or '')
        if not assigned_year:
            raise PermissionError('PIT Leads must have an assigned year level.')
        if year_level and normalize_year_level(year_level) != assigned_year:
            raise PermissionError('PIT Leads can manage only their assigned year level.')
        if team and normalize_year_level(team.year_level) != assigned_year:
            raise PermissionError('PIT Leads can manage only their assigned year level.')
        year_level = assigned_year
    if year_level:
        year_level = normalize_year_level(year_level)
        if year_level not in {'1st Year', '2nd Year', '3rd Year', '4th Year'}:
            raise ValidationError('Invalid year level.')
    semester = team.semester if team else active_semester()
    if not semester:
        raise ValidationError('An active semester is required for program stage access.')
    teams = StudentTeam.objects.filter(pk=team.pk) if team else StudentTeam.objects.filter(semester=semester)
    teams = teams.select_related('semester__school_year')
    teams = teams.filter(level__icontains='PIT') if program_scope == 'pit' else teams.exclude(level__icontains='PIT')
    if year_level:
        teams = teams.filter(year_level=year_level)
    if program_scope == 'capstone':
        from defense.stages.models import DefenseStage
        stages = list(DefenseStage.objects.filter(is_active=True).order_by('display_order').values_list('label', flat=True))
    else:
        from defense.scheduler.models import PitEventGradingConfig
        events = PitEventGradingConfig.objects.filter(semester=semester).exclude(year_level='')
        if year_level:
            events = events.filter(year_level=year_level)
        stages = list(events.order_by('event_name').values_list('event_name', flat=True))
    return teams, stages, semester, program_scope, year_level


def access_payload(user, *, scope='global', team=None, program_scope='capstone', year_level=None):
    from .services import get_deliverable_definitions_for_team, ensure_submission_editable
    from .models import DeliverableSubmission
    teams, stages, semester, program_scope, year_level = _scope(
        user, scope=scope, team=team, program_scope=program_scope, year_level=year_level,
    )
    teams = list(teams)
    rows = []
    submissions = {(item.team_id, item.stage_label, item.deliverable_id): item
                   for item in DeliverableSubmission.objects.filter(team__in=teams)}
    for stage in stages:
        stage_teams = _stage_teams(teams, stage, program_scope)
        row = {'stage_label': stage}
        for kind in ('pre', 'post'):
            allowed = 0
            for item in stage_teams:
                try:
                    ensure_submission_editable(item, stage, kind)
                    allowed += 1
                except PermissionError:
                    pass
            row[kind] = {'allowed_count': allowed, 'team_count': len(stage_teams),
                         'unlocked': allowed > 0, 'mixed': 0 < allowed < len(stage_teams)}
        definitions = get_deliverable_definitions_for_team(stage_teams[0], stage) if stage_teams else []
        row['deliverables'] = []
        for definition in definitions:
            if definition.get('source') == 'defense_minutes':
                continue
            allowed = 0
            archived = 0
            for item in stage_teams:
                submission = submissions.get((item.pk, stage, definition['id']))
                if submission and submission.deliverable_type == 'post' and submission.status == 'accepted':
                    archived += 1
                try:
                    ensure_submission_editable(item, stage, definition['type'], submission,
                                               allow_replacement=True, deliverable_id=definition['id'])
                    allowed += 1
                except PermissionError:
                    pass
            row['deliverables'].append({
                'id': definition['id'], 'label': definition['label'], 'type': definition['type'],
                'allowed_count': allowed, 'team_count': len(stage_teams),
                'unlocked': allowed > 0, 'mixed': 0 < allowed < len(stage_teams),
                'archived_count': archived,
            })
        rows.append(row)
    return {'scope': scope, 'program_scope': program_scope, 'year_level': year_level or '',
            'can_choose_program': bool(user.role == 'admin' or user.is_superuser),
            'semester_id': semester.pk, 'semester_label': f'{semester.school_year.label} · {semester.label}',
            'team_count': len(teams), 'stages': rows}


@transaction.atomic
def set_access(user, *, scope='team', team=None, program_scope='capstone', year_level=None,
               stage_label, unlock_type='all', target_state=None, reason='', request=None, deliverable_id=None):
    from .services import is_stage_unlocked_by_admin
    if unlock_type not in {'pre', 'post', 'all'}:
        raise ValidationError('Invalid file type. Choose pre, post, or all.')
    if target_state is not None and not isinstance(target_state, bool):
        raise ValidationError('target_state must be true or false.')
    if not isinstance(reason, str) or not reason.strip():
        raise ValidationError({'reason': 'Give a reason for changing stage file access.'})
    teams, stages, semester, program_scope, year_level = _scope(
        user, scope=scope, team=team, program_scope=program_scope, year_level=year_level,
    )
    if stage_label not in stages:
        raise ValidationError('The stage is not configured for the selected program and semester.')
    # Lock in a stable order so concurrent team/program changes cannot overwrite each other.
    teams = _stage_teams(list(teams.select_for_update(of=('self',)).order_by('pk')), stage_label, program_scope)
    if not teams:
        raise ValidationError('There are no teams in this stage access scope.')
    definition = None
    if deliverable_id:
        from .services import definition_for
        definition = definition_for(teams[0], stage_label, deliverable_id)
        if not definition or definition.get('source') == 'defense_minutes':
            raise ValidationError('Choose a configured student-uploaded deliverable for this stage.')
        unlock_type = definition['type']
    kinds = ('pre', 'post') if unlock_type == 'all' else (unlock_type,)
    if target_state is None:
        target_state = not bool(teams and all(
            is_stage_unlocked_by_admin(item, stage_label, deliverable_type=kind)
            for item in teams for kind in kinds
        ))
    for item in teams:
        before = sorted(set(item.unlocked_stages or []))
        keys = set(before)
        # Expand legacy blanket grants before editing one file type; preserve the other type.
        if stage_label in keys or f'{stage_label}:all' in keys:
            for kind in ('pre', 'post'):
                if not manually_locked(item, stage_label, kind):
                    keys.add(f'{stage_label}:{kind}')
            keys.discard(stage_label)
            keys.discard(f'{stage_label}:all')
        if deliverable_id:
            key = f'{stage_label}:deliverable:{deliverable_id}'
            keys.discard(key)
            keys.discard(f'{key}:locked')
            keys.add(key if target_state else f'{key}:locked')
        else:
            from .services import get_deliverable_definitions_for_team
            for kind in kinds:
                keys.discard(f'{stage_label}:{kind}')
                keys.discard(f'{stage_label}:{kind}:locked')
                keys.add(f'{stage_label}:{kind}' if target_state else f'{stage_label}:{kind}:locked')
            # A group action replaces earlier individual overrides in that group.
            for config in get_deliverable_definitions_for_team(item, stage_label):
                if config['type'] in kinds:
                    key = f"{stage_label}:deliverable:{config['id']}"
                    keys.discard(key)
                    keys.discard(f'{key}:locked')
        after = sorted(keys)
        if before != after:
            item.unlocked_stages = after
            item.save(update_fields=['unlocked_stages', 'updated_at'])
        from .models import DeliverableSubmission
        submitted = DeliverableSubmission.objects.select_for_update().filter(team=item, stage_label=stage_label)
        if deliverable_id:
            submitted = submitted.filter(deliverable_id=deliverable_id)
        else:
            submitted = submitted.filter(deliverable_type__in=kinds)
        prior_replacements = list(submitted.filter(file_replacement_unlocked=True).values_list('pk', flat=True))
        if deliverable_id and target_state:
            from repository.project_archive.services import request_archive_resubmission
            for submission in submitted.filter(deliverable_type='pre', status='accepted'):
                prefix = 'pit-deliverable' if item.is_pit else 'capstone'
                request_archive_resubmission(user, f'{prefix}-{submission.pk}', 'Approved', reason, request=request)
        elif not target_state:
            submitted.update(file_replacement_unlocked=False, file_replacement_reason='')
        current_replacements = list(submitted.filter(file_replacement_unlocked=True).values_list('pk', flat=True))
        if before == after and prior_replacements == current_replacements:
            continue
        context = {**audit_scope_metadata(scope=program_scope, team=item),
                   'stage_label': stage_label, 'file_type': unlock_type,
                   'access_scope': scope, 'semester_id': semester.pk}
        if deliverable_id:
            context.update(deliverable_id=deliverable_id, deliverable_label=definition['label'])
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_REPOSITORY, action='repository.stage_access_updated',
            target=item, actor=user, request=request, reason=reason.strip(), strict=True,
            old_values={**context, 'unlocked_stages': before, 'replacement_unlocked_submission_ids': prior_replacements},
            new_values={**context, 'unlocked_stages': after, 'upload_allowed': target_state,
                        'replacement_unlocked_submission_ids': current_replacements},
        )
    return target_state
