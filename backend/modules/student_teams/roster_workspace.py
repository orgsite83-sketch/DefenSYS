"""Versioned PIT rosters and event-specific student setup.

Reads are projections only. Signed reviews are revalidated under the same event
locks as first activity. Membership replacements create fresh team identities;
explicit reuse and project edits retain identities and preserve event evidence.
"""
import csv
import io
import json
from hashlib import sha256
from math import ceil
from random import SystemRandom
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.core import signing
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError
from defensys_backend.read_projection import read_memoize

from academic_period_management.models import Semester
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import PitEventGradingConfig
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment
from .formation_access import instructor_sections, require_generation_scope
from .models import StudentTeam, TeamMembership, PITSectionRoster, PITEventRoster, PITRosterTeamDetails, SectionAssignment
from .pit_rosters import resolve, event_in_use, pin
from .team_levels import is_capstone_scope, user_is_admin, user_is_pit_lead_only
from .term_scope import get_active_semester

SALT = 'student-teams.roster-workspace.v1'
YEARS = ('1st Year', '2nd Year', '3rd Year')


def text(value):
    return ' '.join(str(value or '').split())


def require_roster_scope(user, term, year, section, workspace=None, *, allow_empty_section=False):
    if year not in YEARS or is_capstone_scope(year, term) or (not section and not allow_empty_section):
        raise ValidationError('Choose an active PIT year and section.')
    if workspace not in (None, '', 'instructor', 'operations'):
        raise PermissionDenied('Choose an instructor or PIT management workspace.')
    if workspace != 'instructor' and (user_is_admin(user) or (
            user_is_pit_lead_only(user) and text(user.pit_lead_year) == year)):
        return
    if workspace == 'operations':
        raise PermissionDenied('This roster is outside your PIT management year. Use your assigned instructor workspace for other sections.')
    if user.role != 'faculty' or not instructor_sections(user, term, year).filter(section=section).exists():
        raise PermissionDenied('You can manage rosters only for your active assigned PIT sections.')


def choices(user, term, workspace):
    assignments = instructor_sections(user, term)
    result = {(a['year_level'], a['section']) for a in assignments.values('year_level', 'section')}
    if workspace != 'instructor' and (user_is_admin(user) or user_is_pit_lead_only(user)):
        records = StudentAcademicRecord.objects.filter(semester=term)
        teams = StudentTeam.objects.filter(semester=term, level__icontains='PIT')
        sections = SectionAssignment.objects.filter(semester=term)
        instructors = SectionInstructorAssignment.objects.filter(semester=term, is_active=True)
        if not user_is_admin(user):
            records = records.filter(year_level=user.pit_lead_year)
            teams = teams.filter(year_level=user.pit_lead_year)
            sections = sections.filter(year_level=user.pit_lead_year)
            instructors = instructors.filter(year_level=user.pit_lead_year)
            result = {r for r in result if r[0] == user.pit_lead_year}
        result.update(records.values_list('year_level', 'section'))
        result.update(teams.values_list('year_level', 'section'))
        result.update(sections.values_list('year_level', 'section'))
        result.update(instructors.values_list('year_level', 'section'))
    return [{'year_level': y, 'section': s} for y, s in sorted(result)
        if y in YEARS and not is_capstone_scope(y, term) and s and s.upper() != 'BSIT']


def scope(user, data, *, allow_empty_section=False):
    term = get_active_semester()
    if not term:
        raise ValidationError('No active semester is configured.')
    workspace = data.get('workspace') or None
    available = choices(user, term, workspace)
    year, section = text(data.get('year_level')), text(data.get('section'))
    if not year and available:
        year = available[0]['year_level']
    if not year and user_is_pit_lead_only(user) and workspace != 'instructor':
        year = text(user.pit_lead_year)
    if not section:
        section = next((c['section'] for c in available if c['year_level'] == year), '')
    require_roster_scope(user, term, year, section, workspace, allow_empty_section=allow_empty_section)
    return term, year, section, available


def event_for(term, year, value):
    if value in (None, '', 'current'):
        return None
    if isinstance(value, bool) or not str(value).isdigit():
        raise ValidationError('Choose an event from this PIT year and semester.')
    event = PitEventGradingConfig.objects.filter(pk=int(value), semester=term, year_level=year).first()
    if not event:
        raise ValidationError('Choose an event from this PIT year and semester.')
    return event


def details_for(team, event=None):
    rows = list(team.roster_details.all())
    return next((r for r in rows if r.event_id == (event.pk if event else None)), None) or (
        next((r for r in rows if r.event_id is None), None) if event else None)


@read_memoize(copy=True)
def project_for(team, event=None):
    """A declared title never acquires a concept decision by being copied."""
    from repository.deliverables.concepts import latest_round, titles_complete
    from .concept_policy import resolve_policy
    detail = details_for(team, event)
    if not event and detail and detail.details_source_event_id:
        source = next((r for r in team.roster_details.all() if r.event_id == detail.details_source_event_id), None)
        # Corrections await leader confirmation before changing a confirmed
        # current declaration. Concept decisions still resolve from their event.
        if not detail.confirmed_at or source and source.confirmed_at:
            return project_for(team, detail.details_source_event)
    title = detail.project_title if detail else (team.project_title if team.project_title != team.name else '')
    mode = detail.project_mode if detail else 'continue'
    explicit_event = bool(detail and event and detail.event_id == event.pk)
    # A team formed without a project can register it in its first event and
    # continue it later without retyping. Explicit event setup captures its own
    # value; new-project policies never take this fallback.
    if not title and event and (mode == 'continue' or not explicit_event) and not (explicit_event and (detail.opened_at or detail.confirmed_at)):
        previous = [r for r in team.roster_details.all() if r.event_id and r.confirmed_at and r.project_title
            and (not event or r.event_id != event.pk)]
        latest = max(previous, key=lambda r: (r.confirmed_at, r.pk)) if previous else None
        if latest:
            title = latest.project_title
    if event and event.concept_config.get('enabled'):
        current = latest_round(team, event)
        if current:
            selected = [c for c in current.concepts if c.get('decision') in ('approved', 'approved_with_revisions')]
            titles = [text(c.get('title')) for c in (selected or current.concepts) if text(c.get('title'))]
            selected_title = titles[0] if len(selected) == 1 and len(titles) == 1 and not current.replacement_required else ''
            return {'title': '\n'.join(titles), 'status': 'Approved' if selected_title and current.verdict == 'approved' else
                'Selected · revisions pending' if selected_title else 'Proposed',
                'complete': titles_complete(current), 'carry_title': selected_title if current.verdict == 'approved' else '',
                'round_id': current.pk}
        policy = resolve_policy(team, event)
        if policy.get('mode') == 'assigned' and policy.get('assigned_title'):
            assigned = policy['assigned_title']
            return {'title': assigned, 'status': 'Assigned', 'complete': True, 'carry_title': assigned, 'round_id': None}
        from .concept_policy import initial_concepts
        proposals = initial_concepts(policy)
        titles = [c['title'] for c in proposals if c.get('title')]
        return {'title': '\n'.join(titles) or title, 'status': 'Proposed' if titles or title else 'Missing',
            'complete': bool(proposals) and len(titles) == len(proposals), 'carry_title': title, 'round_id': None}
        # A carried identity may be registered for a later concept-enabled event;
        # opening setup explicitly assigns it through the existing policy resolver.
        if explicit_event and mode == 'new':
            title = ''
    return {'title': title, 'status': ('Carried forward' if detail and detail.source_event_id else 'Declared') if title else 'Missing',
        'complete': bool(title), 'carry_title': title, 'round_id': None}


def display_for(team, event=None):
    detail = details_for(team, event)
    if not detail:
        return {'name': team.name, 'project_title': team.project_title}
    return {'name': detail.name if detail else team.name, 'project_title': project_for(team, event)['title']}


def team_rows(term, year, section, event=None):
    from .concept_policy import resolve_policy
    resolved = resolve(term.pk, year, event.pk if event else None).get(section, {})
    teams = StudentTeam.objects.filter(pk__in=resolved.get('team_ids', []), semester=term,
        year_level=year, section=section, level__icontains='PIT').select_related('leader').prefetch_related(
            'memberships__student', 'roster_details')
    busy_ids = project_work_ids(event, resolved.get('team_ids', [])) if event else set()
    result = []
    for team in teams:
        detail = details_for(team, event)
        own = detail if detail and detail.event_id == (event.pk if event else None) else None
        project = project_for(team, event)
        shared = bool(event and event.concept_config.get('enabled') and
            resolve_policy(team, event).get('source') == 'section_system')
        work_started = bool(event and (event.is_officially_complete or team.pk in busy_ids))
        # Retained event configuration is a visible suggestion for unopened
        # teams only. The roster choice now owns the decision, not this field.
        legacy_new = bool(event and not shared and event.project_setup_policy == 'new' and not (own and own.opened_at))
        choice = 'continue' if shared else 'new' if legacy_new or not project['carry_title'] else 'continue'
        members = sorted(team.memberships.all(), key=lambda m: (m.student_id != team.leader_id, m.order, m.student.username))
        confirmed = (bool(own.confirmed_at) if own else bool(not team.roster_identity and event_in_use(event, section) and not team.setup_pending)) if event else (
            bool(detail.confirmed_at) if detail else not team.setup_pending)
        result.append({'id': team.pk, 'name': detail.name if detail else team.name,
            'leader_id': team.leader_id, 'leader_name': team.leader.get_full_name() or team.leader.username,
            'members': [{'id': m.student_id, 'username': m.student.username,
                'name': m.student.get_full_name() or m.student.username, 'is_leader': m.student_id == team.leader_id} for m in members],
            'project_title': project['title'], 'project_status': project['status'], 'carry_title': project['carry_title'],
            'project_mode': detail.project_mode if detail else 'continue', 'project_complete': project['complete'],
            'project_choice': choice, 'shared_project': shared, 'project_locked': work_started,
            'can_change_project': not work_started and not shared,
            'legacy_new_project': legacy_new,
            'confirmed': confirmed, 'setup_opened': bool(own and own.opened_at),
            'ready': bool(confirmed and project['complete'] and members and team.leader_id in [m.student_id for m in members]),
            'details_revision': own.revision if own else None})
    return sorted(result, key=lambda t: (t['name'].casefold(), t['id']))


def project_work_ids(event, team_ids):
    """Read activity in batches so roster controls do not query per team."""
    from repository.deliverables.models import ConceptRound, DeliverableSubmission
    from defense.scheduler.models import DefenseSchedule
    if not event or not team_ids:
        return set()
    result = {r.team_id for r in ConceptRound.objects.filter(team_id__in=team_ids, pit_event_config=event)
        if any(text(c.get('title')) or c.get('decision') or c.get('remarks') for c in r.concepts) or r.endorsed_at
        or r.schedule_id or r.verdict or r.decided_at or r.documents_snapshot or r.endorsement_snapshot
        or r.section_round_id or r.override_reason or not r.review_required or r.revisions_cleared_at or r.replacement_required}
    result.update(DeliverableSubmission.objects.filter(team_id__in=team_ids,
        pit_event_config=event).values_list('team_id', flat=True))
    result.update(DefenseSchedule.objects.filter(team_id__in=team_ids, scope='pit',
        event_name__iexact=event.event_name).values_list('team_id', flat=True))
    result.update(StudentTeam.objects.filter(pk__in=team_ids).filter(Q(grade_records__pit_event_config=event) |
            Q(pit_endorsements__event=event, pit_endorsements__endorsed_at__isnull=False) |
            Q(ready_for_stage__iexact=event.event_name)).values_list('pk', flat=True))
    return result


def project_work_started(event, team_ids):
    return bool(project_work_ids(event, team_ids))


@read_memoize(copy=True)
def roster_payload(term, year, section, event=None):
    resolved = resolve(term.pk, year, event.pk if event else None).get(section, {})
    rows = team_rows(term, year, section, event)
    locked = bool(event and event_in_use(event, section))
    return {'id': event.pk if event else None, 'name': event.event_name if event else 'Current roster',
        'source': resolved.get('source', 'current'), 'revision': resolved.get('revision'),
        'locked': locked, 'completed': bool(event and event.is_officially_complete),
        'needs_selection': resolved.get('needs_selection', False), 'teams': rows,
        'team_count': len(rows), 'student_count': len({m['id'] for t in rows for m in t['members']}),
        'ready_count': sum(t['ready'] for t in rows),
        'concept_enabled': bool(event and event.concept_config.get('enabled')),
        'can_request_setup': bool(rows and (not event or not event.is_officially_complete) and
            any(not t['project_locked'] for t in rows)),
        'can_correct_details': bool(event and not event.is_officially_complete and rows and
            not project_work_started(event, [t['id'] for t in rows])),
        'legacy_new_project': any(t['legacy_new_project'] for t in rows),
        'status': 'Completed · roster locked' if event and event.is_officially_complete else 'Roster locked' if locked else
            'Current roster needs review' if resolved.get('needs_selection') else 'Default for upcoming events' if not event else
            'Custom roster' if resolved.get('source') == 'custom' else 'Uses current roster'}


def context(user, data):
    # Browsing an unsectioned cohort is valid; preview/apply still need a section.
    term, year, section, available = scope(user, data, allow_empty_section=True)
    events = list(PitEventGradingConfig.objects.filter(semester=term, year_level=year).order_by('pk'))
    can_generate = user.role == 'faculty' and instructor_sections(user, term, year).filter(section=section).exists()
    return {'semester_id': term.pk, 'semester': str(term), 'year_level': year, 'section': section or None,
        'scope_options': available, 'can_generate': can_generate,
        'can_import_sections': user_is_pit_lead_only(user) and data.get('workspace') != 'instructor',
        'fingerprint': fingerprint(term, year, section) if section else None,
        'rosters': ([roster_payload(term, year, section)] + [roster_payload(term, year, section, e) for e in events])
            if section else []}


def fingerprint(term, year, section):
    events = list(PitEventGradingConfig.objects.filter(semester=term, year_level=year).order_by('pk'))
    state = {'rosters': [roster_payload(term, year, section)] + [roster_payload(term, year, section, e) for e in events],
        'events': [[e.pk, e.updated_at.isoformat(), e.project_setup_policy, e.concept_config, e.team_membership_policy] for e in events],
        'section_details': list(SectionAssignment.objects.filter(
            semester=term, section=section).values('system_name', 'project_manager_id', 'concept_policies', 'updated_at')),
        'students': list(StudentAcademicRecord.objects.filter(semester=term, year_level=year, section=section).order_by('student_id').values_list(
            'student_id', 'student__is_active', 'student__role', 'student__username'))}
    return sha256(json.dumps(state, sort_keys=True, default=str).encode()).hexdigest()


def validate_rows(term, year, section, rows, event, *, allow_unassigned=False, enrollment=None, conflicts=None):
    if not isinstance(rows, list) or not 0 < len(rows) <= 500:
        raise ValidationError('Prepare between 1 and 500 teams.')
    names, members = [], []
    for row in rows:
        if not isinstance(row, dict):
            raise ValidationError('Every team must be a roster row.')
        name, title = text(row.get('name')), text(row.get('project_title'))
        ids, leader = row.get('member_ids'), row.get('leader_id')
        if len(name) > 120 or len(title) > 255:
            raise ValidationError('Enter a team name up to 120 characters and a project title up to 255 characters.')
        if not isinstance(ids, list) or not 0 < len(ids) <= 4 or any(type(i) is not int for i in ids) or len(ids) != len(set(ids)):
            raise ValidationError(f'{name}: choose between 1 and 4 distinct enrolled members.')
        if type(leader) is not int or leader not in ids:
            raise ValidationError(f'{name}: the leader must be a member of this team.')
        if row.get('section', section) != section:
            raise PermissionDenied('Keep this replacement within the selected assigned section.')
        if name:
            names.append(name.casefold())
        members.extend(ids)
    if len(names) != len(set(names)) or (not event or event.team_membership_policy != 'multiple') and len(members) != len(set(members)):
        raise ValidationError('Resolve repeated team names and students before applying this complete roster.')
    enrollment_sections = Q(section=section)
    if allow_unassigned:
        # A reviewed import can establish a class section; other operations cannot.
        enrollment_sections |= Q(section='') | Q(section__iexact='BSIT')
    enrolled = enrollment if enrollment is not None else set(StudentAcademicRecord.objects.filter(
        enrollment_sections, semester=term, year_level=year, student__is_active=True,
        student__role='student', student_id__in=members).values_list('student_id', flat=True))
    if not set(members).issubset(enrolled):
        raise PermissionDenied('Every member must be an active student enrolled in this section, year and semester.')
    # A replacement cannot borrow another section's event membership policy.
    other = TeamMembership.objects.filter(student_id__in=members, team__semester=term,
        team__year_level=year, team__level__icontains='PIT').exclude(team__section=section)
    from .pit_rosters import membership_queryset
    conflict = bool(set(members).intersection(conflicts)) if conflicts is not None else membership_queryset(other, event.event_name if event else None).exists()
    if (not event or event.team_membership_policy != 'multiple') and conflict:
        raise ValidationError('Some students already belong to a different section roster. Resolve the enrollment conflict first.')


def imported_rows(term, year, section, raw):
    from .bulk_import import resolve_user_by_full_name
    if not isinstance(raw, list) or not 0 < len(raw) <= 500:
        raise ValidationError('Upload between 1 and 500 teams.')
    rows = []
    for row in raw:
        if not isinstance(row, dict):
            raise ValidationError('Every imported team must be a row.')
        members = row.get('member_ids', [])
        if isinstance(members, str):
            members = [v.strip() for v in members.split(';') if v.strip()]
        if not isinstance(members, list):
            raise ValidationError('Each team requires a list of members.')
        ids = []
        for reference in members:
            student, error = resolve_user_by_full_name(str(reference), role='student', field_label='Member')
            if error or not student:
                raise ValidationError(error or 'An imported student account was not found.')
            ids.append(student.pk)
        leader_ref = row.get('leader_id') or (members[0] if members else '')
        leader, error = resolve_user_by_full_name(str(leader_ref), role='student', field_label='Leader')
        if error or not leader:
            raise ValidationError(error or 'Choose a valid team leader.')
        rows.append({'name': text(row.get('team_name') or row.get('name')), 'member_ids': ids,
            'leader_id': leader.pk, 'section': text(row.get('section') or section),
            'project_title': text(row.get('project_title')), 'source_event_id': None, 'source_team_id': None,
            'group_key': text(row.get('group_key')) or f'import/{len(rows)}'})
    return rows


def imported_sheet_details(user, term, year, section, raw, *, member_ids=(), workspace=None):
    """Validate shared-system sheet details without writes during file review."""
    from .bulk_import import resolve_user_by_full_name, validate_bulk_section_metadata
    systems = {text(row.get('system_name')) for row in raw if text(row.get('system_name'))}
    managers = {text(row.get('project_manager')) for row in raw if text(row.get('project_manager'))}
    if len(systems) > 1 or len(managers) > 1:
        raise ValidationError('Use one System Name and Project Manager for this section.')
    system = next(iter(systems), '')
    if len(system) > 255:
        raise ValidationError('System Name must be at most 255 characters.')
    instructor_ids = set()
    for reference in {text(row.get('instructor_name')) for row in raw if text(row.get('instructor_name'))}:
        instructor, error = resolve_user_by_full_name(reference, role=['faculty', 'admin'], field_label='Instructor')
        if error:
            raise ValidationError(error)
        if not instructor or not instructor.is_active:
            raise ValidationError('Choose an active section instructor.')
        if (workspace == 'instructor' or not (user_is_admin(user) or user_is_pit_lead_only(user))) and instructor.pk != user.pk:
            raise PermissionDenied('An instructor import cannot assign another instructor.')
        instructor_ids.add(instructor.pk)
    manager = validate_bulk_section_metadata({
        'system_name': system, 'project_manager': next(iter(managers), ''), 'issues': [],
    }, user, term, year, section, member_ids=member_ids) if system or managers else None
    return {'system_name': system, 'project_manager_id': manager.pk if manager else None,
        'instructor_ids': sorted(instructor_ids)}


def project_selection(rows, data):
    selected = data.get('team_ids', [r['id'] for r in rows if not r['project_locked']])
    if (not isinstance(selected, list) or not selected or any(type(i) is not int for i in selected)
            or len(selected) != len(set(selected)) or not set(selected) <= {r['id'] for r in rows}):
        raise ValidationError('Choose distinct teams in this roster.')
    modes = data.get('team_modes')
    if modes is not None and (not isinstance(modes, dict) or set(modes) != {str(i) for i in selected}):
        raise ValidationError('Choose a project option for every selected team.')
    bulk = data.get('project_mode')
    if bulk is not None and bulk not in ('continue', 'new'):
        raise ValidationError('Choose keep existing project or start new project.')
    result = []
    for row in rows:
        if row['id'] not in selected:
            continue
        if row['project_locked']:
            raise ValidationError(f'{row["name"]}: work has started. Use the existing concept review or revision workflow.')
        mode = modes.get(str(row['id'])) if modes is not None else bulk or row['project_choice']
        if mode not in ('continue', 'new'):
            raise ValidationError('Choose keep existing project or start new project.')
        if row['shared_project'] and mode == 'new':
            raise ValidationError('Shared system and module changes must use the shared concept workflow.')
        if mode == 'continue' and not row['carry_title'] and not row['shared_project']:
            if modes is not None:
                raise ValidationError(f'{row["name"]}: there is no existing project to keep.')
            mode = 'new'  # Compatibility with first-event setup clients.
        result.append({**row, 'project_mode': mode, 'previous_title': row['project_title'],
            'project_title': row['carry_title'] if mode == 'continue' else '',
            'project_action': 'Use shared concept workflow' if row['shared_project'] else
                'Keep existing project' if mode == 'continue' else 'Start new project',
            'needs_project': mode == 'new' and not row['shared_project']})
    return result


def prepare_projects(user, data, term, year, section, event):
    """Review roster project choices without opening tasks or clearing titles."""
    reviewed_fingerprint = fingerprint(term, year, section)
    if event:
        event.refresh_from_db()
    if event and event.is_officially_complete:
        raise ValidationError('This event is complete. Prepare projects in a future roster.')
    rows = team_rows(term, year, section, event)
    selected = project_selection(rows, data)
    choices_by_id = {r['id']: r for r in selected}
    if event:
        prepared = selected
    else:
        # A project change keeps membership identity. Apply freezes event
        # profiles before changing the reusable current details in place.
        prepared = []
        for row in rows:
            choice = choices_by_id.get(row['id'])
            title = choice['project_title'] if choice else row['carry_title']
            prepared.append({**row, 'member_ids': [m['id'] for m in row['members']], 'section': section,
                'project_title': title, 'project_mode': 'continue' if title else 'new',
                'previous_title': row['project_title'],
                'project_action': choice['project_action'] if choice else 'Keep current details',
                'needs_project': not bool(title), 'needs_name': False,
                'source_team_id': row['id'] if title else None, 'source_event_id': None})
        validate_rows(term, year, section, prepared, None)
    affected, preserved = [], []
    for other in PitEventGradingConfig.objects.filter(semester=term, year_level=year):
        resolved = resolve(term.pk, year, other.pk).get(section, {})
        if event:
            (affected if other.pk == event.pk else preserved).append(other.event_name)
        else:
            (affected if not event_in_use(other, section) and resolved.get('source') == 'current' and not
                PITEventRoster.objects.filter(event=other, section=section).exists() else preserved).append(other.event_name)
    payload = {'year_level': year, 'section': section, 'workspace': data.get('workspace'),
        'event_id': event.pk if event else None, 'operation': 'projects',
        'team_ids': [r['id'] for r in selected], 'team_modes': {str(r['id']): r['project_mode'] for r in selected}}
    if reviewed_fingerprint != fingerprint(term, year, section):
        raise ValidationError('This roster changed while preparing the review. Refresh and review the project choices again.')
    state = {'actor': user.pk, 'data': payload, 'rows': prepared,
        'fingerprint': reviewed_fingerprint, 'nonce': uuid4().hex}
    return {'preview_token': signing.dumps(state, salt=SALT, compress=True), 'operation': 'projects',
        'event_setup': bool(event), 'teams': prepared, 'target': event.event_name if event else 'Current roster',
        'team_count': len(selected), 'previous_team_count': len(rows),
        'kept_project_count': sum(r['project_mode'] == 'continue' for r in selected),
        'new_project_count': sum(r['project_mode'] == 'new' for r in selected),
        'affected_events': affected, 'preserved_events': preserved,
        'confirmation': 'Confirm projects & request details' if event else 'Apply project choices to Current roster'}


def prepare(user, data):
    term, year, section, _ = scope(user, data)
    event = event_for(term, year, data.get('event_id'))
    if data.get('operation') == 'projects':
        return prepare_projects(user, data, term, year, section, event)
    if event and event_in_use(event, section):
        raise ValidationError('This event roster is locked. Prepare a new Current roster for upcoming events instead.')
    operation = data.get('operation')
    if operation == 'import' and data.get('validation_only') is True:
        from .import_review import review_roster_import
        return review_roster_import(user, term, year, section, data.get('teams'), event,
            workspace=data.get('workspace'))
    source = None
    if operation in ('copy', 'reuse'):
        source = event_for(term, year, data.get('source_event_id'))
        if operation == 'reuse' and (event or not source):
            raise ValidationError('Choose an event roster to use as Current roster.')
        if (source.pk if source else None) == (event.pk if event else None):
            raise ValidationError('Choose a different source roster.')
        rows = [{'name': t['name'], 'member_ids': [m['id'] for m in t['members']], 'leader_id': t['leader_id'],
            'section': section, 'project_title': t['carry_title'] if data.get('carry_projects', True) else '',
            'source_event_id': source.pk if source else None, 'source_team_id': t['id']}
            for t in team_rows(term, year, section, source)]
    elif operation == 'import':
        rows = imported_rows(term, year, section, data.get('teams'))
    elif operation == 'generate':
        require_generation_scope(user, term, f'{year} PIT', section)
        size = data.get('group_size', 4)
        if type(size) is not int or not 1 <= size <= 4 or data.get('method', 'alphabetical') not in ('alphabetical', 'random'):
            raise ValidationError('Choose alphabetical or random grouping and between 1 and 4 students per team.')
        students = list(StudentAcademicRecord.objects.filter(semester=term, year_level=year, section=section,
            student__is_active=True, student__role='student').select_related('student').order_by(
                'student__last_name', 'student__first_name', 'student__username'))
        ids = [s.student_id for s in students]
        if not ids:
            raise ValidationError('Import and confirm the section class list before generating teams.')
        if 'confirmed_student_ids' in data:
            confirmed = data['confirmed_student_ids']
            if (not isinstance(confirmed, list) or any(type(i) is not int for i in confirmed)
                    or sorted(confirmed) != sorted(ids)):
                raise ValidationError('The section class list changed. Return to the students step and confirm it again.')
        if data.get('method') == 'random':
            SystemRandom().shuffle(ids)
        rows, offset = [], 0
        count = ceil(len(ids) / size)
        base, remainder = divmod(len(ids), count) if count else (0, 0)
        for i in range(count):
            group = ids[offset:offset + base + (i < remainder)]
            offset += len(group)
            rows.append({'name': f'{section} · Team {i + 1:02d}', 'member_ids': group, 'leader_id': group[0],
                'section': section, 'project_title': '', 'source_event_id': None, 'source_team_id': None})
    else:
        raise ValidationError('Choose copy, reuse, import, or generate.')
    existing = team_rows(term, year, section, event)
    current = resolve(term.pk, year).get(section, {})
    initializes_current = bool(event and operation in ('generate', 'import') and
        not current.get('team_ids') and not current.get('needs_selection'))
    for row in rows:
        # Generation always starts fresh, even if deterministic grouping happens
        # to produce the same members. Copying explicitly retains source titles;
        # imported titles are the user's reviewed assignments.
        row['project_mode'] = 'continue' if row['project_title'] else 'new'
        if row['project_mode'] == 'new' and operation != 'reuse':
            row['source_event_id'] = None
    validate_rows(term, year, section, rows, event, allow_unassigned=operation == 'import')
    if initializes_current:
        validate_rows(term, year, section, rows, None, allow_unassigned=operation == 'import')
    if operation == 'import':
        from .bulk_import import imported_concept_requirement
        for row in rows:
            assignment, _ = imported_concept_requirement({
                'team_name': row['name'], 'project_title': row['project_title'],
                'level': f'{year} PIT', 'year_level': year, 'section': section,
                'current_defense_stage': event.event_name if event else None})
            row['concept_assignment'] = assignment
    enrolled = set(StudentAcademicRecord.objects.filter(semester=term, year_level=year, section=section,
        student__is_active=True, student__role='student').values_list('student_id', flat=True))
    used = {i for row in rows for i in row['member_ids']}
    affected, preserved = [], []
    for e in PitEventGradingConfig.objects.filter(semester=term, year_level=year):
        r = resolve(term.pk, year, e.pk).get(section, {})
        uses_new_default = ((not event or initializes_current) and not event_in_use(e, section) and
            r.get('source', 'current') == 'current' and not
            PITEventRoster.objects.filter(event=e, section=section).exists())
        (affected if (initializes_current and e.pk == event.pk) or uses_new_default else preserved).append(e.event_name)
    sheet_details = imported_sheet_details(user, term, year, section, data['teams'], member_ids=used,
        workspace=data.get('workspace')) if operation == 'import' else {}
    state = {'actor': user.pk, 'sheet_details': sheet_details, 'initializes_current': initializes_current,
        'data': {'year_level': year, 'section': section, 'workspace': data.get('workspace'),
        'event_id': event.pk if event else None, 'operation': operation}, 'rows': rows,
        'fingerprint': fingerprint(term, year, section), 'nonce': uuid4().hex}
    people = {u.pk: u for u in get_user_model().objects.filter(pk__in=used)}
    preview_rows = [{**r, 'display_name': r['name'] or f'Unnamed team {index}',
        'needs_name': not bool(r['name']), 'needs_project': not bool(r['project_title']), 'leader_name': people[r['leader_id']].get_full_name() or people[r['leader_id']].username,
        'members': [{'id': i, 'name': people[i].get_full_name() or people[i].username,
            'username': people[i].username} for i in r['member_ids']]} for index, r in enumerate(rows, 1)]
    from .import_review import section_import_summaries
    summaries = section_import_summaries(data['teams'], [], term, import_section=section,
        year=year, user=user) if operation == 'import' else []
    return {'preview_token': signing.dumps(state, salt=SALT, compress=True), 'teams': preview_rows,
        'section_summaries': summaries,
        'target': event.event_name if event else 'Current roster', 'previous_team_count': len(existing),
        'initializes_current': initializes_current,
        'reuses_teams': operation == 'reuse',
        'source_name': source.event_name if source else 'Current roster',
        'team_count': len(rows), 'student_count': len(used), 'omitted_student_count': len(enrolled - used),
        'affected_events': affected, 'preserved_events': preserved,
        'section_assignment_count': StudentAcademicRecord.objects.filter(
            Q(section='') | Q(section__iexact='BSIT'), semester=term, year_level=year,
            student_id__in=used).count() if operation == 'import' else 0,
        'confirmation': 'Use existing teams as Current roster' if operation == 'reuse' else
            'Apply teams & set Current roster' if initializes_current else
            f'Apply to {event.event_name}' if event else 'Set as current roster for upcoming events'}


def lock_cohort(term, year):
    # Serializes two replacements even before a current-roster head exists.
    Semester.objects.select_for_update().get(pk=term.pk)
    return list(PitEventGradingConfig.objects.select_for_update().filter(semester=term, year_level=year).order_by('pk'))


def freeze_events(term, year, section, events):
    for event in events:
        if not event_in_use(event, section):
            continue
        resolved = resolve(term.pk, year, event.pk).get(section, {})
        ids = resolved.get('team_ids', [])
        if not ids:
            if resolved.get('needs_selection'):
                raise ValidationError(f'Review the saved roster for {event.event_name} before changing the default.')
            PITEventRoster.objects.get_or_create(event=event, section=section,
                defaults={'source': 'custom', 'started_at': timezone.now()})
            continue
        pin(StudentTeam.objects.get(pk=ids[0]), event)
        for team in StudentTeam.objects.filter(pk__in=ids).prefetch_related('roster_details'):
            profile = details_for(team, event)
            PITRosterTeamDetails.objects.get_or_create(team=team, event=event, defaults={
                'name': profile.name if profile else team.name, 'project_title': project_for(team, event)['carry_title'],
                'confirmed_at': timezone.now()})


def audit(request, action, target, values):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, action=action,
        request=request, target=target, new_values=values, strict=True)


@transaction.atomic
def apply(request, token):
    try:
        state = signing.loads(token, salt=SALT, max_age=3600)
    except (signing.BadSignature, TypeError) as exc:
        raise ValidationError('This roster review expired. Review the roster again.') from exc
    if state.get('actor') != request.user.pk:
        raise PermissionDenied('This roster review belongs to another user.')
    term, year, section, _ = scope(request.user, state['data'])
    events = lock_cohort(term, year)
    list(get_user_model().objects.select_for_update().filter(pk=request.user.pk))
    list(instructor_sections(request.user, term, year).filter(section=section).select_for_update())
    require_roster_scope(request.user, term, year, section, state['data'].get('workspace'))
    receipt_key = sha256(token.encode()).hexdigest()
    project_setup = state['data']['operation'] == 'projects' and state['data'].get('event_id')
    action = 'teams.roster_setup_open' if project_setup else 'teams.roster_replace'
    previous = SystemAuditLog.objects.filter(actor=request.user, action=action,
        new_values__preview_id=receipt_key).first()
    if previous:
        return previous.new_values
    event = event_for(term, year, state['data'].get('event_id'))
    if state['data']['operation'] == 'generate':
        require_generation_scope(request.user, term, f'{year} PIT', section)
    ids = sorted({i for row in state['rows'] for i in row.get('member_ids', [m['id'] for m in row.get('members', [])])})
    list(get_user_model().objects.select_for_update().filter(pk__in=ids).order_by('pk'))
    list(StudentAcademicRecord.objects.select_for_update().filter(semester=term, student_id__in=ids).order_by('pk'))
    if state['fingerprint'] != fingerprint(term, year, section):
        raise ValidationError('Roster, enrollment, projects or event activity changed. Review the replacement again.')
    if project_setup:
        return apply_event_projects(request, state, term, year, section, event, receipt_key)
    if state['data']['operation'] == 'projects':
        return apply_current_projects(request, state, term, year, section, events, receipt_key)
    if event and event_in_use(event, section):
        raise ValidationError('This event roster is locked. Prepare projects in a future roster.')
    importing = state['data']['operation'] == 'import'
    validate_rows(term, year, section, state['rows'], event, allow_unassigned=importing)
    initializes_current = bool(state.get('initializes_current'))
    if initializes_current:
        current = resolve(term.pk, year).get(section, {})
        if not event or state['data']['operation'] not in ('generate', 'import') or current.get('team_ids') or current.get('needs_selection'):
            raise ValidationError('The Current roster changed. Review the generated teams again.')
        validate_rows(term, year, section, state['rows'], None, allow_unassigned=importing)
    sheet_details = state.get('sheet_details', {})
    instructor_ids = sheet_details.get('instructor_ids', [])
    instructors = list(get_user_model().objects.select_for_update().filter(pk__in=instructor_ids))
    if len(instructors) != len(instructor_ids) or any(not u.is_active or u.role not in ('faculty', 'admin') for u in instructors):
        raise ValidationError('An instructor account changed. Review the roster again.')
    if (state['data'].get('workspace') == 'instructor' or not (user_is_admin(request.user) or user_is_pit_lead_only(request.user))) and any(i != request.user.pk for i in instructor_ids):
        raise PermissionDenied('An instructor import cannot assign another instructor.')
    if importing:
        StudentAcademicRecord.objects.filter(Q(section='') | Q(section__iexact='BSIT'),
            semester=term, year_level=year, student_id__in=ids).update(section=section)
    freeze_events(term, year, section, events)
    # Establish the old default before new unassigned teams can affect inference.
    from .pit_rosters import ensure_current
    if not event and resolve(term.pk, year).get(section, {}).get('needs_selection'):
        # The signed complete replacement is an explicit choice of the new
        # default; protected legacy events have already been frozen above.
        PITSectionRoster.objects.get_or_create(semester=term, year_level=year, section=section)
    else:
        ensure_current(term.pk, year, [section])
    if initializes_current:
        # Recheck after locking the saved default; another roster writer may
        # have populated a previously absent head while this apply waited.
        current_binding = PITSectionRoster.objects.select_for_update().get(
            semester=term, year_level=year, section=section)
        if current_binding.teams.exists():
            raise ValidationError('The Current roster changed. Review the generated teams again.')
    created = []
    for row in state['rows']:
        if state['data']['operation'] == 'reuse':
            team = StudentTeam.objects.select_for_update().get(pk=row['source_team_id'],
                semester=term, year_level=year, section=section, level__icontains='PIT')
            created.append(team)
            continue
        needs_name = not bool(row['name']) or state['data']['operation'] == 'generate'
        name = row['name'] or f'Unnamed team {uuid4().hex}'
        team = StudentTeam.objects.create(name=name, roster_identity=uuid4(), semester=term, year_level=year,
            level=f'{year} PIT', section=section, leader_id=row['leader_id'], project_title=row['project_title'],
            setup_pending=needs_name, project_pending=bool(event and event.concept_config.get('enabled')) or not bool(row['project_title']),
            concept_assignment=row.get('concept_assignment', {'mode': 'assigned', 'assigned_title': row['project_title'], 'project_version': 1}
                if row['project_title'] else {}), current_defense_stage=event.event_name if event else None)
        TeamMembership.objects.bulk_create([TeamMembership(team=team, student_id=i, order=n,
            is_leader=i == row['leader_id']) for n, i in enumerate(row['member_ids'])])
        defaults = {'name': name, 'project_title': row['project_title'], 'project_mode': row.get('project_mode', 'continue'),
            'source_event_id': row.get('source_event_id'),
            'source_team_id': row.get('source_team_id'), 'confirmed_at': None if state['data']['operation'] == 'generate' else timezone.now()}
        PITRosterTeamDetails.objects.create(team=team, **defaults)
        if event:
            PITRosterTeamDetails.objects.create(team=team, event=event, **{**defaults, 'confirmed_at': None,
                'opened_at': timezone.now() if needs_name or not row['project_title'] or event.concept_config.get('enabled') else None})
        created.append(team)
    if event:
        binding, _ = PITEventRoster.objects.select_for_update().get_or_create(event=event, section=section, defaults={'source': 'custom'})
        binding.source = 'custom'
    else:
        binding = PITSectionRoster.objects.select_for_update().get(semester=term, year_level=year, section=section)
    binding.teams.set(created)
    binding.revision += 1
    binding.save()
    if initializes_current:
        current_binding.teams.set(created)
        current_binding.revision += 1
        current_binding.save(update_fields=['revision', 'updated_at'])
    from .current_identity import activate_details, sync_confirmed_details
    for team in created:
        if event:
            activate_details(team, event)
        elif state['data']['operation'] == 'reuse':
            source_id = next(r['source_event_id'] for r in state['rows'] if r['source_team_id'] == team.pk)
            source = event_for(term, year, source_id)
            activate_details(team, source, explicit=True)
            sync_confirmed_details(team, source)
    if sheet_details.get('system_name') or sheet_details.get('project_manager_id'):
        from .section_access import require_section_write, audit_section
        manager = get_user_model().objects.filter(pk=sheet_details.get('project_manager_id')).first()
        require_section_write(request.user, term, year, section, manager)
        existing = SectionAssignment.objects.select_for_update().filter(semester=term, section=section).first()
        old = {'system_name': existing.system_name, 'project_manager_id': existing.project_manager_id} if existing else {}
        assignment, created_assignment = SectionAssignment.objects.update_or_create(semester=term, section=section, defaults={
            'year_level': year, 'system_name': sheet_details.get('system_name') or (existing.system_name if existing else ''),
            'project_manager': manager or (existing.project_manager if existing else None)})
        audit_section(request, assignment, 'section_assignment.create' if created_assignment else 'section_assignment.update', old)
    if state['data'].get('workspace') != 'instructor' and (user_is_admin(request.user) or user_is_pit_lead_only(request.user)):
        for instructor_id in instructor_ids:
            SectionInstructorAssignment.objects.update_or_create(faculty_id=instructor_id,
                semester=term, year_level=year, section=section,
                defaults={'assigned_by': request.user, 'is_active': True})
    result = {'team_ids': [t.pk for t in created],
        'created_count': 0 if state['data']['operation'] == 'reuse' else len(created),
        'reused_count': len(created) if state['data']['operation'] == 'reuse' else 0, 'preview_id': receipt_key,
        'initializes_current': initializes_current,
        'event_id': event.pk if event else None, 'section': section, 'operation': state['data']['operation']}
    audit(request, 'teams.roster_replace', binding, result)
    return result


def apply_current_projects(request, state, term, year, section, events, receipt_key):
    """Changing a project keeps team/member identities and freezes history."""
    freeze_events(term, year, section, events)
    selected = set(state['data']['team_ids'])
    for row in state['rows']:
        if row['id'] not in selected:
            continue
        team = StudentTeam.objects.select_for_update().get(pk=row['id'], semester=term,
            year_level=year, section=section)
        profile, _ = PITRosterTeamDetails.objects.select_for_update().get_or_create(
            team=team, event=None, defaults={'name': team.name})
        profile.project_title, profile.project_mode = row['project_title'], row['project_mode']
        profile.details_source_event = None
        profile.confirmed_at = profile.confirmed_at if row['project_title'] else None
        profile.revision += 1
        profile.save()
        team.project_title, team.project_pending = row['project_title'], not bool(row['project_title'])
        team.save(update_fields=['project_title', 'project_pending', 'updated_at'])
    result = {'team_ids': list(selected), 'requested_count': len(selected),
        'created_count': 0, 'section': section, 'event_id': None,
        'operation': 'projects', 'preview_id': receipt_key}
    audit(request, 'teams.roster_replace', term, result)
    return result


def apply_event_projects(request, state, term, year, section, event, receipt_key):
    """Apply the signed per-team choices while the cohort/event locks are held."""
    if not event or event.is_officially_complete:
        raise ValidationError('Choose an upcoming event to request project setup.')
    original_rows = {row['id']: row for row in team_rows(term, year, section, event)}
    choices = project_selection(list(original_rows.values()), state['data'])
    selected = {row['id']: row for row in choices}
    all_ids = resolve(term.pk, year, event.pk).get(section, {}).get('team_ids', [])
    pin(StudentTeam.objects.get(pk=all_ids[0]), event)
    for team in StudentTeam.objects.filter(pk__in=all_ids).prefetch_related('roster_details'):
        base = details_for(team, event)
        original = original_rows[team.pk]
        detail, _ = PITRosterTeamDetails.objects.get_or_create(team=team, event=event, defaults={
            'name': original['name'], 'project_title': original['carry_title'],
            'source_event_id': base.source_event_id if base else None,
            'source_team_id': base.source_team_id if base else None,
            'confirmed_at': timezone.now() if original['confirmed'] else None})
        if team.pk not in selected:
            continue
        choice = selected[team.pk]
        mode = choice['project_mode']
        detail.project_mode = mode
        detail.project_title = choice['project_title']
        if mode == 'new':
            detail.source_event = None
            detail.source_team = None
        detail.opened_at, detail.confirmed_at = timezone.now(), None
        detail.revision += 1
        detail.save()
        from .current_identity import activate_details
        activate_details(team, event, explicit=True)
        if event.concept_config.get('enabled'):
            from .concept_policy import resolve_policy, team_policy_key, initial_concepts
            current_policy = resolve_policy(team, event, use_round=False)
            if current_policy.get('source') != 'section_system':
                team.concept_policies = {**team.concept_policies, team_policy_key(team, event):
                    {'mode': 'proposals', 'seed_title': detail.project_title if mode == 'continue' else ''}}
                team.save(update_fields=['concept_policies', 'updated_at'])
                # Display-created empty drafts have no student work or hearing
                # evidence. Keep them aligned with the newly reviewed choice.
                from repository.deliverables.concepts import latest_round
                current = latest_round(team, event)
                if current:
                    policy = resolve_policy(team, event, use_round=False)
                    current.policy_snapshot, current.concepts = policy, initial_concepts(policy)
                    current.save(update_fields=['policy_snapshot', 'concepts'])
    result = {'requested_count': len(selected), 'section': section, 'team_ids': list(selected),
        'event_id': event.pk, 'team_modes': state['data']['team_modes'], 'preview_id': receipt_key, 'operation': 'projects'}
    audit(request, 'teams.roster_setup_open', event, result)
    return result


@transaction.atomic
def open_setup(request, data):
    """Compatibility entrypoint; the roster UI uses signed review and apply."""
    term, year, section, _ = scope(request.user, data)
    lock_cohort(term, year)
    if data.get('fingerprint') != fingerprint(term, year, section):
        raise ValidationError('This roster changed. Refresh and review project setup again.')
    preview = prepare(request.user, {**data, 'operation': 'projects'})
    return apply(request, preview['preview_token'])


def setup_tasks(user):
    from .concept_policy import resolve_policy, title_progress
    from repository.deliverables.concepts import latest_round
    rows = PITRosterTeamDetails.objects.filter(event__isnull=False, opened_at__isnull=False,
        team__semester=get_active_semester(), team__leader=user, team__memberships__student=user,
        event__is_officially_complete=False).select_related('event', 'team').distinct()
    result = []
    for detail in rows:
        team, event = detail.team, detail.event
        if team.pk not in resolve(team.semester_id, team.year_level, event.pk).get(team.section, {}).get('team_ids', []):
            continue
        project = project_for(team, event)
        if detail.confirmed_at and project['complete']:
            continue
        policy = resolve_policy(team, event) if event.concept_config.get('enabled') else {}
        result.append({'id': team.pk, 'event_id': event.pk, 'event_name': event.event_name,
            'name': f'Unnamed team {team.pk}' if team.setup_pending else detail.name,
            'needs_name': team.setup_pending,
            'section': team.section, 'scope': 'pit', 'year_level': team.year_level, 'revision': detail.revision,
            'needs_details': not bool(detail.confirmed_at), 'concept_enabled': bool(event.concept_config.get('enabled')),
            'project_title': detail.project_title, 'project_complete': project['complete'],
            'concept_tasks': [{'stage_label': event.event_name, **title_progress(policy, latest_round(team, event)),
                'mode': policy.get('mode', 'proposals'), 'shared_system': policy.get('source') == 'section_system'}]
                if event.concept_config.get('enabled') and not project['complete'] else []})
    return result


@transaction.atomic
def confirm_setup(request, team_id, event_id, data):
    term = get_active_semester()
    if term:
        Semester.objects.select_for_update().get(pk=term.pk)
    event = PitEventGradingConfig.objects.select_for_update().filter(pk=event_id,
        semester=get_active_semester(), is_officially_complete=False).first()
    if not event:
        raise ValidationError('This event setup is closed.')
    detail = PITRosterTeamDetails.objects.select_for_update().filter(team_id=team_id, event=event,
        opened_at__isnull=False, team__leader=request.user, team__memberships__student=request.user).first()
    if not detail or request.user.role != 'student':
        raise PermissionDenied('Only this event team’s leader can confirm its details.')
    if detail.revision != data.get('revision') or detail.confirmed_at:
        raise ValidationError('These details changed or are already confirmed. Refresh your tasks.')
    if detail.team_id not in resolve(event.semester_id, event.year_level, event.pk).get(detail.team.section, {}).get('team_ids', []):
        raise PermissionDenied('This team is outside the event roster.')
    name = text(data.get('name'))
    title = detail.project_title if event.concept_config.get('enabled') and 'project_title' not in data else text(data.get('project_title'))
    if not name or len(name) > 120 or len(title) > 255:
        raise ValidationError('Enter a team name up to 120 characters and a project title up to 255 characters.')
    if PITRosterTeamDetails.objects.filter(event=event, team__section=detail.team.section, name__iexact=name).exclude(pk=detail.pk).exists():
        raise ValidationError('Another team in this event section uses that name.')
    if event.concept_config.get('enabled'):
        if title and title != detail.project_title:
            raise ValidationError('Enter concept titles through the existing concept workflow.')
    elif not title:
        raise ValidationError('Enter or confirm the project title for this event.')
    else:
        detail.project_title = title
    detail.name, detail.confirmed_at = name, timezone.now()
    detail.revision += 1
    detail.save()
    from .current_identity import activate_details, sync_confirmed_details
    activate_details(detail.team, event)
    sync_confirmed_details(detail.team, event)
    # An imported event team has its own identity. Do not rewrite the names
    # of a Current roster or historical event snapshots when confirming it.
    if detail.team.setup_pending and detail.team.current_defense_stage == event.event_name:
        detail.team.setup_pending = False
        detail.team.save(update_fields=['setup_pending', 'updated_at'])
    audit(request, 'teams.event_details_confirm', detail, {'event_id': event.pk, 'team_id': team_id, 'name': name})
    return {'event_teams': setup_tasks(request.user)}


def export_roster(user, data):
    term, year, section, _ = scope(user, data)
    event = event_for(term, year, data.get('event_id'))
    payload = roster_payload(term, year, section, event)
    if not payload['teams']:
        raise ValidationError('There are no teams to export in this roster.')
    draft = payload['ready_count'] != payload['team_count']
    headers = ['Team Name', 'Project / Module', 'Section', 'Leader', 'Team Members', 'Project Status', 'Information Status']
    rows = [[t['name'], t['project_title'], section, t['leader_name'], '\n'.join(m['name'] for m in t['members']),
        t['project_status'], 'Confirmed' if t['ready'] else 'Awaiting details'] for t in payload['teams']]
    def safe(value):
        value = str(value)
        return "'" + value if value.lstrip().startswith(('=', '+', '-', '@', '\t', '\r')) else value
    stream = io.StringIO(newline='')
    writer = csv.writer(stream)
    writer.writerow(headers)
    writer.writerows([[safe(v) for v in row] for row in rows])
    return {'filename': f'PIT-{section}-{event.event_code or event.pk if event else "current"}{"-draft" if draft else ""}',
        'draft': draft, 'event': payload['name'], 'semester': str(term), 'section': section,
        'headers': headers, 'rows': rows, 'csv': '\ufeff' + stream.getvalue()}


@transaction.atomic
def correct_details(request, data):
    term, year, section, _ = scope(request.user, data)
    lock_cohort(term, year)
    event = event_for(term, year, data.get('event_id'))
    if not event or event.is_officially_complete:
        raise ValidationError('Choose a preparing event to correct its team details.')
    ids = resolve(term.pk, year, event.pk).get(section, {}).get('team_ids', [])
    team_id = data.get('team_id')
    if type(team_id) is not int or team_id not in ids:
        raise PermissionDenied('Choose a team in this event and assigned section.')
    if project_work_started(event, ids):
        raise ValidationError('Event work has started. Use the existing review or revision workflow.')
    detail = PITRosterTeamDetails.objects.select_for_update().filter(team_id=team_id, event=event).first()
    if not detail or detail.revision != data.get('revision'):
        raise ValidationError('Team details changed. Refresh this roster before correcting them.')
    name = text(data.get('name'))
    title = detail.project_title if event.concept_config.get('enabled') and 'project_title' not in data else text(data.get('project_title'))
    if not name or len(name) > 120 or len(title) > 255:
        raise ValidationError('Enter a team name up to 120 characters and a project title up to 255 characters.')
    if event.concept_config.get('enabled') and title != detail.project_title:
        raise ValidationError('Concept titles must follow the existing concept review and revision workflow.')
    if PITRosterTeamDetails.objects.filter(event=event, team__section=section, name__iexact=name).exclude(pk=detail.pk).exists():
        raise ValidationError('Another team in this event section uses that name.')
    detail.name = name
    if not event.concept_config.get('enabled'):
        detail.project_title = title
    detail.confirmed_at = None
    detail.revision += 1
    detail.save()
    audit(request, 'teams.event_details_correct', detail, {'team_id': team_id, 'event_id': event.pk, 'section': section})
    return {'corrected': True}
