from django.db.models import Q

from academic_period_management.models import SchoolYear
from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import (
    STAGE_OPTIONS,
    deliverable_definitions_for_stage,
    stage_payload,
    vault_unlocked,
)
from repository.vault.models import VaultEntry
from student_teams.models import StudentTeam

from .constants import STATUS_OPTIONS, SUBMISSION_KIND_OPTIONS, TYPE_OPTIONS
from .payloads import (
    _missing_capstone_entry,
    capstone_entry_payload,
)


def _capstone_teams_queryset():
    return StudentTeam.objects.select_related(
        'semester',
        'semester__school_year',
    ).filter(level__icontains='Capstone')


def _pit_teams_queryset():
    return StudentTeam.objects.select_related(
        'semester',
        'semester__school_year',
    ).filter(level__icontains='PIT')


def teams_for_track(track):
    if track == 'capstone':
        return _capstone_teams_queryset()
    if track == 'pit':
        return _pit_teams_queryset()
    return StudentTeam.objects.select_related(
        'semester',
        'semester__school_year',
    ).filter(Q(level__icontains='Capstone') | Q(level__icontains='PIT'))


def track_from_entry_type(entry_type):
    normalized = (entry_type or '').strip()
    if normalized == VaultEntry.TYPE_CAPSTONE:
        return 'capstone'
    if normalized == VaultEntry.TYPE_PIT:
        return 'pit'
    return 'all'


def normalize_team_id(team_id):
    if team_id is None:
        return None
    try:
        return int(team_id)
    except (TypeError, ValueError):
        return None


def team_track(level):
    if 'Capstone' in (level or ''):
        return 'capstone'
    if 'PIT' in (level or ''):
        return 'pit'
    return ''


def team_counts_payload(entries, track='all'):
    tallies = {
        team.id: {
            'id': team.id,
            'name': team.name,
            'level': team.level,
            'year_level': team.year_level,
            'track': team_track(team.level),
            'pre': 0,
            'vault': 0,
            'archive': 0,
            'total': 0,
        }
        for team in teams_for_track(track)
    }
    for entry in entries:
        team_id = normalize_team_id(entry.get('team_id'))
        if team_id is None or team_id not in tallies:
            continue
        bucket = tallies[team_id]
        kind = entry.get('submission_kind') or ''
        if track == 'capstone' and kind == 'pit':
            continue
        if track == 'pit' and kind in ('pre', 'vault', 'archive'):
            continue
        if kind == 'pre' and not entry.get('is_missing'):
            bucket['pre'] += 1
        elif kind == 'vault' and not entry.get('is_missing'):
            bucket['vault'] += 1
        elif kind == 'archive':
            bucket['archive'] += 1
        elif kind == 'pit':
            bucket['archive'] += 1
        if entry.get('has_file') or entry.get('is_missing'):
            bucket['total'] += 1
    return sorted(tallies.values(), key=lambda item: (item['level'] or '', item['name'] or ''))


def teams_options_from_counts(team_counts):
    options = []
    for row in team_counts:
        level = row.get('level') or ''
        name = row.get('name') or 'Team'
        label = f'{name} · {level}' if level else name
        options.append({
            'id': row['id'],
            'name': name,
            'level': level,
            'value': str(row['id']),
            'label': label,
        })
    return options


def deliverable_options_payload(entries):
    seen = set()
    options = []
    for entry in entries:
        deliverable_id = (entry.get('deliverable_id') or '').strip()
        if not deliverable_id or deliverable_id in seen:
            continue
        seen.add(deliverable_id)
        label = entry.get('deliverable_label') or deliverable_id
        options.append({
            'value': deliverable_id,
            'label': label,
            'submission_kind': entry.get('submission_kind') or '',
        })
    options.sort(key=lambda item: item['value'])
    return [{'value': '', 'label': 'All deliverables'}] + options


def options_payload(entries, track='all'):
    year_levels = sorted({entry['year_level'] for entry in entries if entry.get('year_level')})
    academic_years = {entry['academic_year'] for entry in entries if entry.get('academic_year')}
    academic_years.update(SchoolYear.objects.values_list('label', flat=True))
    semesters = sorted({entry['semester'] for entry in entries if entry.get('semester')})
    stages = sorted({entry['stage'] for entry in entries if entry.get('stage')})
    team_counts = team_counts_payload(entries, track=track)
    return {
        'type_options': TYPE_OPTIONS,
        'status_options': STATUS_OPTIONS,
        'submission_kind_options': SUBMISSION_KIND_OPTIONS,
        'year_levels': sorted(set(['1st Year', '2nd Year', '3rd Year', '4th Year'] + year_levels)),
        'academic_years': sorted(academic_years, reverse=True),
        'semesters': sorted(set(['1st Semester', '2nd Semester', 'Summer'] + semesters)),
        'stage_options': sorted(set(STAGE_OPTIONS + stages)),
        'teams': teams_options_from_counts(team_counts),
        'deliverable_options': deliverable_options_payload(entries),
        'team_counts': team_counts,
    }


def _checklist_for_team_stage(team, stage_label):
    payload = stage_payload(team, stage_label)
    return {
        'pre_required_missing': [
            item['id']
            for item in payload['deliverables']
            if item['type'] == DeliverableSubmission.TYPE_PRE
            and item['required']
            and not item['uploaded']
        ],
        'vault_locked_ids': [
            item['id']
            for item in payload['deliverables']
            if item['type'] == DeliverableSubmission.TYPE_VAULT and item['locked']
        ],
        'vault_missing_ids': [
            item['id']
            for item in payload['deliverables']
            if item['type'] == DeliverableSubmission.TYPE_VAULT
            and not item['uploaded']
            and not item['locked']
        ],
    }


def _entries_for_stage_deliverables(
    team,
    stage_label,
    entries_for_team,
    request=None,
    *,
    include_ml=False,
    include_audit_trail=False,
):
    submissions = {
        submission.deliverable_id: submission
        for submission in team.deliverable_submissions.all()
        if submission.stage_label == stage_label
    }
    pre_defense = []
    vault = []
    payload_kwargs = {
        'request': request,
        'include_ml': include_ml,
        'include_audit_trail': include_audit_trail,
    }
    for definition in deliverable_definitions_for_stage(stage_label):
        submission = submissions.get(definition['id'])
        if submission:
            payload = capstone_entry_payload(submission, **payload_kwargs)
            if payload['submission_kind'] == 'pre':
                pre_defense.append(payload)
            else:
                vault.append(payload)
            continue
        if definition['type'] == DeliverableSubmission.TYPE_VAULT:
            if not vault_unlocked(team, stage_label):
                vault.append(_missing_capstone_entry(team, stage_label, definition, request=request))
            elif definition.get('required'):
                vault.append(_missing_capstone_entry(team, stage_label, definition, request=request))
        elif definition.get('required'):
            pre_defense.append(_missing_capstone_entry(team, stage_label, definition, request=request))

    included_source_ids = {
        entry.get('source_id')
        for entry in pre_defense + vault
        if entry.get('source_id')
    }
    for submission in team.deliverable_submissions.all():
        if submission.stage_label != stage_label:
            continue
        if submission.id in included_source_ids:
            continue
        payload = capstone_entry_payload(submission, **payload_kwargs)
        if payload['submission_kind'] == 'pre':
            pre_defense.append(payload)
        elif payload['submission_kind'] == 'vault':
            vault.append(payload)
        included_source_ids.add(submission.id)

    included_ids = {
        entry.get('id')
        for entry in pre_defense + vault
        if entry.get('id')
    }
    archive = [
        entry
        for entry in entries_for_team
        if entry.get('submission_kind') == 'archive'
        and entry.get('stage') == stage_label
        and entry.get('id') not in included_ids
    ]
    return pre_defense, vault, archive


def grouped_by_stage_for_team(
    team,
    entries,
    stage_filter='',
    request=None,
    *,
    include_ml=False,
    include_audit_trail=False,
):
    entries_for_team = [
        entry
        for entry in entries
        if normalize_team_id(entry.get('team_id')) == team.id
    ]
    stages = [stage_filter] if stage_filter else list(STAGE_OPTIONS)
    groups = []
    for stage_name in stages:
        if stage_filter and stage_name != stage_filter:
            continue
        pre_defense, vault, archive = _entries_for_stage_deliverables(
            team,
            stage_name,
            entries_for_team,
            request=request,
            include_ml=include_ml,
            include_audit_trail=include_audit_trail,
        )
        if not (pre_defense or vault or archive) and not stage_filter:
            continue
        groups.append({
            'stage': stage_name,
            'pre_defense': pre_defense,
            'vault': vault,
            'archive': archive,
            'checklist': _checklist_for_team_stage(team, stage_name),
        })
    return groups


def augment_deliverable_missing_rows(entries, deliverable_id, stage_filter=''):
    deliverable_id = (deliverable_id or '').strip()
    if not deliverable_id:
        return entries

    existing_keys = {
        (entry.get('team_id'), entry.get('stage'), entry.get('deliverable_id'))
        for entry in entries
        if entry.get('deliverable_id') == deliverable_id and not entry.get('is_missing')
    }
    augmented = list(entries)
    teams = _capstone_teams_queryset().prefetch_related('deliverable_submissions')
    stages = [stage_filter] if stage_filter else STAGE_OPTIONS

    for team in teams:
        for stage_label in stages:
            definitions = deliverable_definitions_for_stage(stage_label)
            definition = next((item for item in definitions if item['id'] == deliverable_id), None)
            if not definition:
                continue
            key = (team.id, stage_label, deliverable_id)
            if key in existing_keys:
                continue
            submitted = {
                submission.deliverable_id
                for submission in team.deliverable_submissions.all()
                if submission.stage_label == stage_label
            }
            if deliverable_id in submitted:
                continue
            if not definition.get('required'):
                continue
            augmented.append(_missing_capstone_entry(team, stage_label, definition))
    return augmented


def deliverable_summary_payload(deliverable_id, entries, stage_filter=''):
    deliverable_id = (deliverable_id or '').strip()
    label = deliverable_id
    kind = ''
    for entry in entries:
        if entry.get('deliverable_id') == deliverable_id:
            label = entry.get('deliverable_label') or deliverable_id
            kind = entry.get('submission_kind') or kind
            break
    if not kind:
        for stage_label in STAGE_OPTIONS:
            definitions = deliverable_definitions_for_stage(stage_label)
            definition = next((item for item in definitions if item['id'] == deliverable_id), None)
            if definition:
                label = definition['label']
                kind = definition['type']
                break
    if kind == DeliverableSubmission.TYPE_VAULT:
        kind = 'vault'
    elif kind == DeliverableSubmission.TYPE_PRE:
        kind = 'pre'

    scoped = [entry for entry in entries if entry.get('deliverable_id') == deliverable_id]
    if stage_filter:
        scoped = [entry for entry in scoped if entry.get('stage') == stage_filter]
    uploaded = sum(1 for entry in scoped if entry.get('has_file') and not entry.get('is_missing'))
    missing = sum(1 for entry in scoped if entry.get('is_missing'))
    return {
        'deliverable_id': deliverable_id,
        'label': label,
        'submission_kind': kind if kind in ('pre', 'vault') else (
            'vault' if kind == DeliverableSubmission.TYPE_VAULT else 'pre'
        ),
        'uploaded_count': uploaded,
        'missing_count': missing,
        'team_count': len({entry.get('team_id') for entry in scoped if entry.get('team_id')}),
    }


def resolve_team_view_error(team, track):
    if track == 'capstone' and not team.is_capstone:
        return 'This team is not on the Capstone track. Switch to the PIT tab or pick a Capstone team.'
    if track == 'pit' and not team.is_pit:
        return 'This team is not on the PIT track. Switch to the Capstone tab or pick a PIT team.'
    if track == 'capstone' and team.is_capstone:
        return ''
    if track in ('all', '') and team.is_capstone:
        return ''
    if track == 'pit' and team.is_pit:
        return ''
    if track in ('all', ''):
        return ''
    return 'Team track does not match the active filter tab.'
