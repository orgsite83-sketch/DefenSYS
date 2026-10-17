"""Section roster grouping and atomic creation. Previewing never writes data."""
from collections import Counter
from math import ceil
from random import SystemRandom

from django.contrib.auth import get_user_model
from django.core import signing
from django.db import transaction
from django.db.models import Count
from rest_framework.exceptions import PermissionDenied, ValidationError

from academic_period_management.capstone_mode import assert_capstone_team_creation_allowed
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.event_scope import pit_events_for_user, require_event_management
from user_management.academic_records.models import StudentAcademicRecord
from .membership_policy import pit_event_memberships
from .models import StudentTeam, TeamMembership
from .serializers import StudentTeamWriteSerializer
from .team_levels import user_is_admin, user_is_pit_lead_only
from .term_scope import assert_active_semester_for_create, get_active_semester

SALT = 'student-teams.formation.v1'


def formation_scope(user, data, *, lock=False):
    if not (user_is_admin(user) or user_is_pit_lead_only(user)):
        raise PermissionDenied('Only administrators and PIT leads can form teams.')
    semester = get_active_semester()
    if not semester:
        raise ValidationError('No active semester is configured.')
    assert_active_semester_for_create(user, semester)
    level = data.get('level', '')
    if level not in dict(StudentTeam.LEVEL_CHOICES):
        raise ValidationError({'level': 'Select a program and year level.'})
    year = level.rsplit(' ', 1)[0]
    if user_is_pit_lead_only(user) and (
            'PIT' not in level or year != user.pit_lead_year):
        raise PermissionDenied('This roster is outside your assigned PIT year level.')
    event = None
    if 'PIT' in level:
        events = pit_events_for_user(user, semester=semester).filter(year_level=year)
        if lock:
            events = events.select_for_update()
        event = events.filter(event_name=data.get('event_name', '')).first()
        if not event:
            raise ValidationError({'event_name': 'Select a PIT event for this year level.'})
        if event.is_officially_complete:
            raise ValidationError('This PIT event is complete; its team roster is read-only.')
    else:
        try:
            assert_capstone_team_creation_allowed(semester)
        except ValueError as exc:
            raise ValidationError(str(exc)) from exc
    return semester, level, year, event


def roster(semester, level, year, event):
    records = StudentAcademicRecord.objects.filter(
        semester=semester, year_level=year, student__role='student', student__is_active=True,
    ).exclude(section='').select_related('student').order_by(
        'section', 'student__last_name', 'student__first_name', 'student__username', 'student_id')
    assigned = TeamMembership.objects.filter(team__semester=semester)
    if event:
        assigned = pit_event_memberships(assigned.filter(team__level__icontains='PIT'), event.event_name)
        excluded = set() if event.team_membership_policy == 'multiple' else set(assigned.values_list('student_id', flat=True))
    else:
        excluded = set(assigned.filter(team__level__icontains='Capstone').values_list('student_id', flat=True))
    return [{
        'id': record.student_id, 'name': record.student.get_full_name() or record.student.username,
        'username': record.student.username, 'section': record.section,
        'eligible': record.student_id not in excluded,
    } for record in records]


def options(user, data):
    semester, level, year, event = formation_scope(user, data)
    students = roster(semester, level, year, event)
    sections = sorted({s['section'] for s in students})
    sources = StudentTeam.objects.filter(semester=semester, level=level).prefetch_related('memberships')
    if event:
        sources = sources.exclude(current_defense_stage=event.event_name)
    else:
        sources = sources.none()
    return {
        'students': students,
        'sections': [{'name': section,
                      'eligible_count': sum(s['eligible'] for s in students if s['section'] == section),
                      'total_count': sum(s['section'] == section for s in students)} for section in sections],
        'source_teams': [{'id': t.pk, 'name': t.name, 'section': t.section,
                          'event_name': t.current_defense_stage or 'General PIT', 'leader_id': t.leader_id,
                          'member_ids': [m.student_id for m in t.memberships.all()]} for t in sources],
        'team_membership_policy': event.team_membership_policy if event else 'single',
        'event_id': event.pk if event else None,
        'semester_id': semester.pk,
    }


def snapshot(user, semester, level, event, sections, students):
    return {'actor': user.pk, 'semester': semester.pk, 'level': level,
            'event': event.pk if event else None,
            'policy': event.team_membership_policy if event else 'single',
            'sections': sorted(sections),
            'students': sorted([[s['id'], s['section']] for s in students if s['eligible'] and s['section'] in sections])}


def preview(user, data):
    semester, level, year, event = formation_scope(user, data)
    students = roster(semester, level, year, event)
    sections = data['sections']
    if len(sections) != len(set(sections)) or not set(sections) <= {s['section'] for s in students}:
        raise ValidationError({'sections': 'Choose existing sections from the current roster.'})
    selected = [s for s in students if s['eligible'] and s['section'] in sections]
    if not selected:
        raise ValidationError('No eligible students are available in these sections.')
    size, method = data['group_size'], data['method']
    groups, used = [], set()
    if method == 'reuse':
        if not event:
            raise ValidationError('Roster reuse is available for PIT events.')
        sources = StudentTeam.objects.filter(pk__in=data.get('source_team_ids', []),
            semester=semester, level=level).exclude(current_defense_stage=event.event_name).prefetch_related('memberships')
        if not sources or sources.count() != len(set(data.get('source_team_ids', []))):
            raise ValidationError('Choose existing teams from another event in this cohort.')
        eligible = {s['id']: s for s in selected}
        for team in sources:
            ids = [m.student_id for m in team.memberships.all()]
            if not ids or any(i not in eligible or i in used or eligible[i]['section'] != team.section for i in ids):
                raise ValidationError('Reused teams must have available, non-overlapping members in the selected sections.')
            groups.append({'section': team.section, 'member_ids': ids, 'leader_id': team.leader_id})
            used.update(ids)
    rng = SystemRandom()
    for section in sections:
        members = [s['id'] for s in selected if s['section'] == section and s['id'] not in used]
        if method == 'random':
            rng.shuffle(members)
        if not members:
            continue
        count = ceil(len(members) / size)
        base, remainder = divmod(len(members), count)
        offset = 0
        for index in range(count):
            length = base + (index < remainder)
            ids = members[offset:offset + length]
            offset += length
            groups.append({'section': section, 'member_ids': ids,
                           'leader_id': rng.choice(ids) if method == 'random' else ids[0]})
    existing = set(StudentTeam.objects.filter(level=level).values_list('name', flat=True))
    for index, group in enumerate(groups, 1):
        stem = f'{group["section"]} · Team {index:02d}'
        if event:
            stem = f'{group["section"]} · {event.event_name[:40]} · Team {index:02d}'
        name, suffix = stem[:110], 1
        while name in existing:
            suffix += 1
            name = f'{stem[:110]} ({suffix})'
        existing.add(name)
        group['name'] = name
    return {'teams': groups, 'students': selected,
            'preview_token': signing.dumps(snapshot(user, semester, level, event, sections, students), salt=SALT)}


@transaction.atomic
def create_from_preview(request, data):
    semester, level, year, event = formation_scope(request.user, data, lock=True)
    try:
        expected = signing.loads(data['preview_token'], salt=SALT, max_age=3600)
    except signing.BadSignature as exc:
        raise ValidationError('This preview expired or is invalid. Generate a fresh preview.') from exc
    # All requests acquire stable student locks before checking availability.
    expected_ids = [row[0] for row in expected.get('students', [])]
    list(get_user_model().objects.select_for_update().filter(pk__in=expected_ids).order_by('pk'))
    students = roster(semester, level, year, event)
    actual = snapshot(request.user, semester, level, event, data['sections'], students)
    if expected != actual:
        raise ValidationError('The roster or event policy changed. Generate a fresh preview before creating teams.')
    drafts = data['teams']
    ids = [i for team in drafts for i in team['member_ids']]
    if Counter(ids) != Counter(expected_ids):
        raise ValidationError('Every previewed student must appear exactly once in this batch.')
    by_id = {s['id']: s for s in students}
    names = [t['name'].strip() for t in drafts]
    if len(names) != len(set(names)):
        raise ValidationError('Each generated team needs a different name.')
    teams = []
    for draft in drafts:
        if data['method'] != 'reuse' and len(draft['member_ids']) > data['group_size']:
            raise ValidationError('A team exceeds the selected maximum team size.')
        if any(by_id[i]['section'] != draft['section'] for i in draft['member_ids']):
            raise ValidationError('Keep each student within their enrolled section.')
        serializer = StudentTeamWriteSerializer(data={
            **draft, 'level': level, 'year_level': year, 'semester_id': semester.pk,
            'project_title': '', 'current_defense_stage': event.event_name if event else None,
        }, context={'assigned_by': request.user, 'user': request.user})
        serializer.is_valid(raise_exception=True)
        teams.append(serializer.save(setup_pending=True))
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, action='teams.generate',
        target=teams[0], request=request, strict=True,
        new_values={'team_ids': [t.pk for t in teams], 'semester_id': semester.pk,
                    'level': level, 'event_name': event.event_name if event else '', 'method': data['method']})
    return teams


@transaction.atomic
def update_event_policy(request, event_id, policy):
    from defense.scheduler.models import PitEventGradingConfig
    from django.shortcuts import get_object_or_404
    event = get_object_or_404(PitEventGradingConfig.objects.select_for_update(), pk=event_id)
    require_event_management(request.user, event)
    assert_active_semester_for_create(request.user, event.semester)
    if event.is_officially_complete:
        raise ValidationError('Completed events are read-only.')
    if policy == 'single':
        duplicates = pit_event_memberships(TeamMembership.objects.filter(
            team__semester=event.semester, team__level__icontains='PIT'), event.event_name
        ).values('student_id').annotate(teams=Count('team_id', distinct=True)).filter(teams__gt=1)
        if duplicates.exists():
            raise ValidationError('Some students already have multiple teams in this event. Adjust those rosters before selecting one team per student.')
    previous = event.team_membership_policy
    event.team_membership_policy = policy
    event.save(update_fields=['team_membership_policy', 'updated_at'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action='pit_event.team_membership_policy', target=event, request=request, strict=True,
        old_values={'team_membership_policy': previous}, new_values={'team_membership_policy': policy})
    return event
