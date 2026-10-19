"""Section roster grouping and atomic creation. Previewing never writes data."""
from collections import Counter
from math import ceil
from random import SystemRandom
from hashlib import sha256
from uuid import uuid4

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
from .formation_access import allowed_sections, require_formation_scope, require_generation_scope, instructor_sections, is_manager

SALT = 'student-teams.formation.v1'


def formation_scope(user, data, *, lock=False, roster_only=False, generation=True):
    semester = get_active_semester()
    if not semester:
        raise ValidationError('No active semester is configured.')
    assert_active_semester_for_create(user, semester)
    level = data.get('level', '')
    if level not in dict(StudentTeam.LEVEL_CHOICES):
        raise ValidationError({'level': 'Select a program and year level.'})
    year = level.rsplit(' ', 1)[0]
    (require_generation_scope if generation else require_formation_scope)(user, semester, level)
    if user_is_pit_lead_only(user) and (
            'PIT' not in level or year != user.pit_lead_year):
        raise PermissionDenied('This roster is outside your assigned PIT year level.')
    event = None
    if 'PIT' in level:
        if not data.get('event_name'):
            return semester, level, year, None
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


def roster(semester, level, year, event, user=None, *, generation=True):
    records = StudentAcademicRecord.objects.filter(
        semester=semester, year_level=year, student__role='student', student__is_active=True,
    ).select_related('student').order_by(
        'section', 'student__last_name', 'student__first_name', 'student__username', 'student_id')
    permitted = (set(instructor_sections(user, semester, year).values_list('section', flat=True))
                 if generation else allowed_sections(user, semester, year)) if user else None
    if permitted is not None:
        records = records.filter(section__in=permitted)
    assigned = TeamMembership.objects.filter(team__semester=semester)
    if event:
        assigned = pit_event_memberships(assigned.filter(team__level__icontains='PIT'), event.event_name)
        excluded = set() if event.team_membership_policy == 'multiple' else set(assigned.values_list('student_id', flat=True))
    elif 'PIT' not in level:
        excluded = set(assigned.filter(team__level__icontains='Capstone').values_list('student_id', flat=True))
    else:
        assigned = pit_event_memberships(assigned.filter(team__level__icontains='PIT'), None)
        excluded = set(assigned.values_list('student_id', flat=True))
    assigned_ids = set(assigned.values_list('student_id', flat=True)) if event else excluded
    return [{
        'id': record.student_id, 'name': record.student.get_full_name() or record.student.username,
        'username': record.student.username, 'section': record.section,
        'assigned': record.student_id in assigned_ids,
        'eligible': record.student_id not in excluded,
    } for record in records]


def options(user, data, *, generation=True):
    semester, level, year, event = formation_scope(user, data, roster_only=True, generation=generation)
    students = roster(semester, level, year, event, user, generation=generation)
    sections = {s['section'] for s in students if s['section'] and s['section'].upper() != 'BSIT'}
    from user_management.models import SectionInstructorAssignment
    assignments = instructor_sections(user, semester, year)
    sections = sorted(sections | set(assignments.values_list('section', flat=True)))
    sources = StudentTeam.objects.filter(semester=semester, level=level).prefetch_related('memberships')
    if event:
        sources = sources.exclude(current_defense_stage=event.event_name)
    else:
        sources = sources.none()
    sources = sources.filter(section__in=sections)
    from defense.stages.models import DefenseStage
    if 'PIT' in level:
        contexts = ([event] if event.concept_config.get('enabled') else []) if event else list(
            pit_events_for_user(user, semester=semester).filter(year_level=year,
                concept_config__enabled=True, is_officially_complete=False).order_by('pk'))
    else:
        contexts = list(DefenseStage.objects.filter(concept_config__enabled=True).order_by('display_order'))
    reviewers = get_user_model().objects.filter(role='faculty', is_active=True)
    if not is_manager(user):
        reviewers = reviewers.filter(pk__in=assignments.values('faculty_id'))
    section_instructors = {}
    for assignment in SectionInstructorAssignment.objects.filter(semester=semester,
            year_level=year, section__in=sections, is_active=True, faculty__is_active=True).values(
                'section', 'faculty_id', 'faculty__first_name', 'faculty__last_name').distinct():
        section_instructors.setdefault(assignment.pop('section'), []).append(assignment)
    return {
        'concept_contexts': [{'label': c.label} for c in contexts],
        'system_reviewers': [{'id': r.pk, 'name': r.get_full_name() or r.username} for r in reviewers.order_by('last_name', 'pk')],
        'section_instructors': section_instructors,
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
        'can_manage_policy': is_manager(user),
        'unassigned_count': sum(not s['section'] or s['section'].upper() == 'BSIT' for s in students),
    }


def snapshot(user, semester, level, event, sections, students, selected_ids=None):
    return {'actor': user.pk, 'semester': semester.pk, 'level': level,
            'event': event.pk if event else None,
            'policy': event.team_membership_policy if event else 'single',
            'sections': sorted(sections),
            'students': sorted([[s['id'], s['section']] for s in students if s['eligible'] and
                (s['id'] in selected_ids if selected_ids is not None else s['section'] in sections)])}


def preview(user, data):
    semester, level, year, event = formation_scope(user, data)
    students = roster(semester, level, year, event, user)
    if not data.get('include_assigned', False):
        students = [{**s, 'eligible': s['eligible'] and not s['assigned']} for s in students]
    sections = data['sections']
    shared_system = data.get('shared_system')
    if shared_system and (data.get('roster_mode', 'sections') != 'sections' or len(sections) != 1):
        raise ValidationError('Generate a shared system for one enrolled section at a time.')
    if shared_system:
        generation_concept_context(event, shared_system, semester=semester, pit_year=year if 'PIT' in level else None)
    custom = data.get('roster_mode', 'sections') == 'custom'
    if not custom and (len(sections) != len(set(sections)) or not set(sections) <= {
            s['section'] for s in students if s['section'] and s['section'].upper() != 'BSIT'}):
        raise ValidationError({'sections': 'Choose existing sections from the current roster.'})
    selected_ids = data.get('student_ids', []) if custom else None
    if custom and (not selected_ids or not set(selected_ids) <= {s['id'] for s in students if s['eligible']}):
        raise ValidationError('Select available students from your authorized roster.')
    selected = [s for s in students if s['eligible'] and
        (s['id'] in selected_ids if custom else s['section'] in sections)]
    if not selected:
        raise ValidationError('No eligible students are available in these sections.')
    size, method = data['group_size'], data['method']
    groups, used = [], set()
    leader_method = data.get('leader_method', 'random' if method == 'random' else 'first')
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
            if not ids or any(i not in eligible or eligible[i]['section'] != team.section for i in ids):
                raise ValidationError('Reused teams must have available members in the selected sections.')
            if event.team_membership_policy != 'multiple' and used.intersection(ids):
                raise ValidationError('These rosters overlap. Allow multiple teams in this event or choose non-overlapping rosters.')
            groups.append({'section': team.section, 'member_ids': ids, 'leader_id': team.leader_id})
            used.update(ids)
    rng = SystemRandom()
    for section in (sorted({s['section'] for s in selected}) if custom else sections):
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
    for group in groups:
        if leader_method == 'random':
            group['leader_id'] = rng.choice(group['member_ids'])
        elif leader_method == 'manual':
            group['leader_id'] = None
        elif leader_method == 'keep' and not group.get('leader_id'):
            group['leader_id'] = group['member_ids'][0]
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
    state = snapshot(user, semester, level, event, sections, students, selected_ids)
    state.update(nonce=uuid4().hex, roster_mode='custom' if custom else 'sections',
                 group_size=size, method=method)
    if shared_system:
        state['shared_system'] = shared_system
    return {'teams': groups, 'students': selected,
            'preview_token': signing.dumps(state, salt=SALT, compress=True)}


@transaction.atomic
def create_from_preview(request, data):
    semester, level, year, event = formation_scope(request.user, data, lock=True)
    try:
        expected = signing.loads(data['preview_token'], salt=SALT, max_age=3600)
    except signing.BadSignature as exc:
        raise ValidationError('This preview expired or is invalid. Generate a fresh preview.') from exc
    fingerprint = sha256(data['preview_token'].encode()).hexdigest()
    # A durable audit receipt makes a retry safe even when multiple teams are allowed.
    list(get_user_model().objects.select_for_update().filter(pk=request.user.pk))
    receipt = SystemAuditLog.objects.filter(actor=request.user, action='teams.generate',
        new_values__preview_id=fingerprint).first()
    if receipt:
        return list(StudentTeam.objects.filter(pk__in=receipt.new_values['team_ids']))
    # All requests acquire stable student locks before checking availability.
    expected_ids = [row[0] for row in expected.get('students', [])]
    list(get_user_model().objects.select_for_update().filter(pk__in=expected_ids).order_by('pk'))
    students = roster(semester, level, year, event, request.user)
    if not data.get('include_assigned', False):
        students = [{**s, 'eligible': s['eligible'] and not s['assigned']} for s in students]
    custom = data.get('roster_mode', 'sections') == 'custom'
    actual = snapshot(request.user, semester, level, event, data['sections'], students,
        data.get('student_ids', []) if custom else None)
    actual.update(nonce=expected.get('nonce'), roster_mode='custom' if custom else 'sections',
                  group_size=data['group_size'], method=data['method'])
    if data.get('shared_system'):
        actual['shared_system'] = data['shared_system']
    if expected != actual:
        raise ValidationError('The roster or event policy changed. Generate a fresh preview before creating teams.')
    drafts = data['teams']
    ids = [i for team in drafts for i in team['member_ids']]
    if event and event.team_membership_policy == 'multiple':
        if set(ids) != set(expected_ids):
            raise ValidationError('Include every previewed student and use only students from this roster.')
    elif Counter(ids) != Counter(expected_ids):
        raise ValidationError('Every previewed student must appear exactly once in this batch under the selected membership policy.')
    by_id = {s['id']: s for s in students}
    names = [t['name'].strip() for t in drafts]
    if len(names) != len(set(names)):
        raise ValidationError('Each generated team needs a different name.')
    from .pit_rosters import ensure_current
    if 'PIT' in level and not event:
        ensure_current(semester.pk, year, {d['section'] for d in drafts})
    teams = []
    for draft in drafts:
        if len(draft['member_ids']) != len(set(draft['member_ids'])):
            raise ValidationError('A student may only appear once within an individual team.')
        if data['method'] != 'reuse' and len(draft['member_ids']) > data['group_size']:
            raise ValidationError('A team exceeds the selected maximum team size.')
        if any(by_id[i]['section'] != draft['section'] for i in draft['member_ids']):
            raise ValidationError('Keep each student within their enrolled section.')
        serializer = StudentTeamWriteSerializer(data={
            **draft, 'level': level, 'year_level': year, 'semester_id': semester.pk,
            'project_title': '', 'current_defense_stage': event.event_name if event else None,
        }, context={'assigned_by': request.user, 'user': request.user, 'preserve_section': True,
                    'formation': True})
        serializer.is_valid(raise_exception=True)
        teams.append(serializer.save(setup_pending=True))
    from .pit_rosters import register
    # Ordinary generation creates the reusable current roster. Legacy clients
    # can still generate for an explicitly selected event they own.
    if not event:
        register(teams, request.user)
    if data.get('shared_system'):
        from repository.section_concepts.services import configure
        configure(request.user, teams, generation_concept_context(event, data['shared_system'],
            semester=semester, pit_year=year if 'PIT' in level else None), data['shared_system'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, action='teams.generate',
        target=teams[0], request=request, strict=True,
        new_values={'team_ids': [t.pk for t in teams], 'semester_id': semester.pk,
                    'level': level, 'event_name': event.event_name if event else '', 'method': data['method'],
                    'preview_id': fingerprint})
    return teams


def generation_concept_context(event, data, *, semester=None, pit_year=None):
    if event:
        context = event
    elif pit_year:
        from defense.scheduler.models import PitEventGradingConfig
        context = PitEventGradingConfig.objects.filter(semester=semester, year_level=pit_year,
            event_name=data.get('stage_label'), concept_config__enabled=True,
            is_officially_complete=False).first()
    else:
        from defense.stages.models import DefenseStage
        context = DefenseStage.objects.filter(label=data.get('stage_label'), concept_config__enabled=True).first()
    if not context or not context.concept_config.get('enabled'):
        raise ValidationError('Select a stage/event with concept selection enabled for the shared system.')
    return context


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
