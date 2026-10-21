"""Current section rosters, event exceptions and immutable in-use membership.

Reads resolve legacy sources without creating records. Event activity pins its
actual team set; current-roster changes subsequently affect unused events only.
"""
from collections import defaultdict
from contextlib import contextmanager
from contextvars import ContextVar

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from defensys_backend.read_projection import read_memoize
from .models import StudentTeam, PITSectionRoster, PITEventRoster

_replacement = ContextVar('pit_roster_replacement', default=None)


def legacy_event_ids(queryset, event):
    return set(queryset.filter(Q(current_defense_stage__iexact=event.event_name) |
        Q(ready_for_stage__iexact=event.event_name) |
        Q(pit_endorsements__event=event, pit_endorsements__endorsed_at__isnull=False) |
        Q(defense_schedules__scope='pit', defense_schedules__event_name__iexact=event.event_name) |
        Q(concept_rounds__pit_event_config=event) |
        Q(deliverable_submissions__pit_event_config=event) |
        Q(grade_records__pit_event_config=event)).values_list('pk', flat=True).distinct())


@read_memoize(copy=True)
def resolve(semester_id, year_level, event_id=None):
    from defense.scheduler.models import PitEventGradingConfig
    all_teams = StudentTeam.objects.filter(semester_id=semester_id, year_level=year_level,
        level__icontains='PIT').order_by('pk')
    records = list(all_teams.values('id', 'section', 'current_defense_stage'))
    sections = defaultdict(list)
    for team in records:
        sections[team['section']].append(team)
    explicit = {r.section: r for r in PITSectionRoster.objects.filter(
        semester_id=semester_id, year_level=year_level).prefetch_related('teams')}
    sections.update({s: sections.get(s, []) for s in explicit})
    event = PitEventGradingConfig.objects.filter(pk=event_id, semester_id=semester_id, year_level=year_level).first() if event_id else None
    if event_id and not event:
        return {}
    bindings = {r.section: r for r in PITEventRoster.objects.filter(event=event).prefetch_related('teams')} if event else {}
    legacy = legacy_event_ids(all_teams, event) if event else set()
    members = defaultdict(set)
    for team_id, student_id in all_teams.values_list('pk', 'memberships__student_id'):
        if student_id:
            members[team_id].add(student_id)
    result = {}
    for section, teams in sections.items():
        head = explicit.get(section)
        ambiguous = False
        if head:
            current_ids = [t.pk for t in head.teams.all()]
        else:
            unassigned = [t for t in teams if not t['current_defense_stage']]
            candidates = unassigned or teams
            labels = {t['current_defense_stage'] or '' for t in candidates}
            student_ids = [sid for t in candidates for sid in members[t['id']]]
            ambiguous = len(labels) > 1 or len(student_ids) != len(set(student_ids))
            current_ids = [] if ambiguous else [t['id'] for t in candidates]
        row = bindings.get(section)
        event_legacy = [t['id'] for t in teams if t['id'] in legacy]
        source, ids, started = 'current', current_ids, None
        if row:
            source, ids, started = row.source, [t.pk for t in row.teams.all()], row.started_at
        elif event_legacy and not set(event_legacy).issubset(current_ids):
            source, ids = 'custom', event_legacy
        legacy_in_use = bool(event and not row and event_in_use(event, section))
        result[section] = {'section': section, 'source': source, 'team_ids': ids,
            'team_count': len(ids), 'needs_selection': ambiguous and not head and not row and not event_legacy,
            'revision': head.revision if head else None,
            'in_use': bool(started) or legacy_in_use, 'started_at': started.isoformat() if started else None,
            'source_label': 'Roster saved for this event' if started or legacy_in_use else 'Current roster needs review' if ambiguous and not head and not row and not event_legacy else 'Custom roster' if source == 'custom' else 'Uses current roster' if event else 'Current roster'}
    return result


def effective_ids(semester_id, year_level, event=None):
    return {pk for row in resolve(semester_id, year_level, event.pk if event else None).values() for pk in row['team_ids']}


def filter_teams(queryset, event_name=None, *, current=False):
    from defense.scheduler.models import PitEventGradingConfig
    allowed = set()
    for semester_id, year in queryset.filter(level__icontains='PIT').order_by().values_list('semester_id', 'year_level').distinct():
        event = PitEventGradingConfig.objects.filter(semester_id=semester_id, year_level=year, event_name__iexact=event_name).first() if event_name else None
        if event_name and not event:
            continue
        allowed.update(effective_ids(semester_id, year, event))
    return queryset.filter(Q(pk__in=allowed) | (Q(level__icontains='Capstone') if current else Q(pk__in=[])))


def membership_queryset(queryset, event_name):
    # Explicit replacement imports validate against the replacement file, rather
    # than treating the roster being replaced as a second team in the same event.
    replacement = _replacement.get()
    teams = filter_teams(StudentTeam.objects.filter(pk__in=queryset.values('team_id')), event_name, current=not event_name)
    # Ambiguous legacy rosters still reserve their students until a lead has
    # explicitly chosen a current roster; ambiguity must never enable duplicates.
    if not event_name:
        unresolved = queryset.filter(team__current_pit_rosters__isnull=True,
            team__pit_event_rosters__isnull=True)
        teams = teams | StudentTeam.objects.filter(pk__in=unresolved.values('team_id'))
    if replacement and event_name == replacement['event_name']:
        teams = teams.exclude(section__in=replacement['sections'])
    return queryset.filter(team__in=teams)


@read_memoize
def event_in_use(event, section):
    if event.is_officially_complete:
        return True
    teams = StudentTeam.objects.filter(semester_id=event.semester_id, year_level=event.year_level,
        section=section, level__icontains='PIT')
    from repository.deliverables.models import ConceptRound
    concept_work = any(any(c.get('title', '').strip() for c in row.concepts) or row.endorsed_at
        for row in ConceptRound.objects.filter(team__in=teams, pit_event_config=event))
    return (PITEventRoster.objects.filter(event=event, section=section, started_at__isnull=False).exists()
        or concept_work or teams.filter(Q(ready_for_stage__iexact=event.event_name) |
            Q(pit_endorsements__event=event, pit_endorsements__endorsed_at__isnull=False) |
            Q(section_project_links__project__pit_event_config=event) |
            Q(deliverable_submissions__pit_event_config=event) |
            Q(defense_schedules__scope='pit', defense_schedules__event_name__iexact=event.event_name) |
            Q(grade_records__pit_event_config=event)).exists())


@transaction.atomic
def ensure_current(semester_id, year, sections):
    """Materialize an inferred default before a write can alter legacy hints."""
    current = resolve(semester_id, year)
    for section in sections:
        source = current.get(section, {})
        if source.get('needs_selection'):
            raise ValidationError('Several legacy rosters exist in this section. Ask your PIT lead to choose the current roster before adding teams.')
        row, created = PITSectionRoster.objects.select_for_update().get_or_create(
            semester_id=semester_id, year_level=year, section=section)
        if created:
            row.teams.set(source.get('team_ids', []))


@contextmanager
def replacement_import(actor, event, sections, enabled=False):
    if not enabled:
        yield
        return
    from defense.scheduler.event_scope import require_event_management
    if not event:
        raise ValidationError('Select an event before importing a different roster.')
    require_event_management(actor, event)
    if event.is_officially_complete or any(event_in_use(event, s) for s in sections):
        raise ValidationError('This event roster is already in use. Its memberships cannot be replaced by an import.')
    token = _replacement.set({'event_name': event.event_name, 'sections': set(sections)})
    try:
        yield
    finally:
        _replacement.reset(token)


@transaction.atomic
def register(teams, actor, *, event=None, replace=False):
    grouped = defaultdict(list)
    for team in teams:
        if team.is_pit:
            grouped[(team.semester_id, team.year_level, team.section)].append(team)
    for (semester_id, year, section), section_teams in grouped.items():
        if event:
            from .roster_workspace import require_roster_scope
            require_roster_scope(actor, event.semester, event.year_level, section)
            if event_in_use(event, section):
                raise ValidationError('The event roster changed or is already in use. Review the import again.')
            row, _ = PITEventRoster.objects.select_for_update().get_or_create(event=event, section=section,
                defaults={'source': 'custom'})
            if row.started_at:
                raise ValidationError('This event roster is already in use.')
            row.source = 'custom'
            row.save(update_fields=['source', 'updated_at'])
            row.teams.set(section_teams) if replace else row.teams.add(*section_teams)
        else:
            existing = resolve(semester_id, year).get(section, {}).get('team_ids', [])
            row, created = PITSectionRoster.objects.select_for_update().get_or_create(
                semester_id=semester_id, year_level=year, section=section)
            if created:
                row.teams.set(StudentTeam.objects.filter(pk__in=existing))
            row.teams.add(*section_teams)
            row.revision += 1
            row.save(update_fields=['revision', 'updated_at'])


@transaction.atomic
def pin(team, event):
    if not team.is_pit:
        return
    from defense.scheduler.models import PitEventGradingConfig
    # Roster commits take this same lock before replacing an unused event.
    event = PitEventGradingConfig.objects.select_for_update().get(pk=event.pk)
    section = resolve(team.semester_id, team.year_level, event.pk).get(team.section)
    if not section or team.pk not in section['team_ids']:
        raise ValidationError('This team is not part of the roster used by this event.')
    if section['source'] == 'current':
        current, created = PITSectionRoster.objects.select_for_update().get_or_create(
            semester_id=team.semester_id, year_level=team.year_level, section=team.section)
        if created:
            current.teams.set(section['team_ids'])
        section['revision'] = current.revision
    row, _ = PITEventRoster.objects.select_for_update().get_or_create(event=event, section=team.section,
        defaults={'source': section['source'], 'current_revision': section['revision']})
    if not row.started_at:
        row.teams.set(section['team_ids'])
        row.started_at = timezone.now()
        row.save(update_fields=['started_at'])
    elif not row.teams.filter(pk=team.pk).exists():
        raise ValidationError('The event roster changed. Refresh before submitting.')


def protect_membership(team, member_ids, leader_id, *, name=None, section=None):
    if not team.is_pit:
        return
    changed = (set(team.memberships.values_list('student_id', flat=True)) != set(member_ids)
        or team.leader_id != leader_id or (name is not None and name != team.name)
        or (section is not None and section != team.section))
    from defense.scheduler.models import PitEventGradingConfig
    completed_use = changed and any(team.pk in effective_ids(team.semester_id, team.year_level, event)
        for event in PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
            year_level=team.year_level, is_officially_complete=True))
    if changed and (completed_use or team.pit_event_rosters.filter(started_at__isnull=False).exists()
            or team.concept_rounds.exists() or team.defense_schedules.filter(scope='pit').exists()
            or team.deliverable_submissions.exists() or team.grade_records.exists()):
        raise ValidationError('This roster is already used by an event. Keep its memberships and name; create a new roster for future events.')


@read_memoize
def endorsed(team, stage_label):
    """Endorsement belongs to one event, even when teams share a roster."""
    from defense.scheduler.models import PitEventGradingConfig
    from .models import PITTeamEventEndorsement
    event = PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
        year_level=team.year_level, event_name__iexact=stage_label).first()
    if not event:
        return False
    from repository.deliverables.concepts import enabled, clearance_valid
    if enabled(event):
        return clearance_valid(team, event)
    record = PITTeamEventEndorsement.objects.filter(team=team, event=event,
        project_version=team.project_version).first()
    return bool(record.endorsed_at) if record else team.ready_for_stage == stage_label


@transaction.atomic
def set_endorsed(team, stage_label, value, actor=None):
    from defense.scheduler.models import PitEventGradingConfig
    from .models import PITTeamEventEndorsement
    event = PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
        year_level=team.year_level, event_name__iexact=stage_label).first()
    if event:
        if value:
            # Preserve the one endorsement older versions stored on the team
            # before updating that compatibility mirror to a different event.
            if team.ready_for_stage and team.ready_for_stage != stage_label:
                previous = PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
                    year_level=team.year_level, event_name__iexact=team.ready_for_stage).first()
                if previous:
                    PITTeamEventEndorsement.objects.get_or_create(team=team, event=previous,
                        project_version=team.project_version,
                        defaults={'endorsed_at': timezone.now()})
                    if team.pk in effective_ids(team.semester_id, team.year_level, previous):
                        pin(team, previous)
            pin(team, event)
        PITTeamEventEndorsement.objects.update_or_create(team=team, event=event,
            project_version=team.project_version,
            defaults={'endorsed_at': timezone.now() if value else None, 'endorsed_by': actor if value else None})
