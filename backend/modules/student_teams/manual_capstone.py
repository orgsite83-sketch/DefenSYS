"""Explicit admin recognition of existing Capstone 2 participation.

The normal intake/import allocator stays closed. Recognition is not a grade,
retry grant, or permission to replace conflicting academic evidence.
"""
import hashlib
import json
from uuid import UUID

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as ModelValidationError
from django.utils import timezone
from rest_framework.exceptions import ValidationError, PermissionDenied

from academic_period_management.models import Semester
from .models import (StudentTeam, StudentCapstoneParticipation as Participation,
                     StudentCapstonePlacement as Placement, CapstoneRosterConfirmation)
from .team_levels import user_is_admin


def batch_term(team):
    """Scheduling scope, which may be a real registration term, not an intake."""
    return team.intake_semester or team.capstone_registration_semester


def batch_id(team):
    return team.intake_semester_id or team.capstone_registration_semester_id


def recorded_intake_id(student_ids):
    latest = {}
    for row in Participation.objects.filter(student_id__in=student_ids).order_by('student_id', '-number'):
        latest.setdefault(row.student_id, row.intake_semester_id)
    ids = set(latest.values())
    return ids.pop() if set(latest) == set(student_ids) and len(ids) == 1 and None not in ids else None


def capacity_candidate(data):
    """Use an evidenced intake/identity for workload checks, never a client ID."""
    from .participation import roster_ids
    student_ids = set(data['member_ids'])
    placements = list(Placement.objects.filter(participation__student_id__in=student_ids,
        participation__state=Participation.ACTIVE, ended_at__isnull=True).select_related('team'))
    sources = {p.team_id for p in placements}
    if len(sources) == 1:
        source = placements[0].team
        if source.semester_id != data['semester'].pk and roster_ids(source) == student_ids and source.project_title.strip().casefold() == data.get('project_title', '').strip().casefold():
            return source
    return StudentTeam(level=StudentTeam.LEVEL_4_CAPSTONE, semester=data['semester'],
        intake_semester_id=recorded_intake_id(student_ids), capstone_registration_semester=data['semester'])


def fingerprint(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


def replay(actor, payload):
    confirmation = payload.get('capstone2_confirmation')
    if not isinstance(confirmation, dict) or not confirmation.get('request_id'):
        return None
    if not user_is_admin(actor):
        raise PermissionDenied('Only administrators can confirm Capstone 2 eligibility.')
    try:
        request_id = UUID(str(confirmation['request_id']))
    except (ValueError, TypeError, AttributeError):
        raise ValidationError({'capstone2_confirmation': 'Use a valid request ID.'})
    row = CapstoneRosterConfirmation.objects.select_related('team').filter(request_id=request_id).first()
    if row:
        if row.actor_id != actor.pk or row.fingerprint != fingerprint(payload):
            raise ValidationError({'capstone2_confirmation': 'This request ID was already used for different data.'})
        return row.team
    return None


def evidence_for(student_id, *, target=None):
    """Return existing authoritative evidence, or require an external reference."""
    from .participation import previous_evidence, require_open, closed_failure
    from .capstone_lifecycle import requirements_for, latest_stage_assessment, stage_cleared
    from .capstone_context import phase_for, inherited_stage_ids
    row = Participation.objects.filter(student_id=student_id).order_by('-number').first()
    if row and row.state != Participation.ACTIVE:
        raise ValidationError(f'The applicable participation is {row.get_state_display()}; it cannot be reopened by team registration.')
    placements = list(row.placements.select_related('team__semester__school_year').order_by('-pk')) if row else []
    source = placements[0].team if placements else None
    if source and target and source.pk == target.pk:
        require_open(source)
        return {'kind': 'recorded', 'participation_id': row.pk}
    if not source:
        if row:
            raise ValidationError('The recorded participation has no reliable placement history. Review that record first.')
        history = previous_evidence(student_id, exclude_team=target.pk if target else None)
        if history:
            raise ValidationError('Existing academic history requires review before this placement.')
        return {'kind': 'external'}
    if source.participation_review_reason or closed_failure(source):
        raise ValidationError('The existing project is Failed or requires historical review.')
    latest_term = source.term_participations.filter(project_version=source.project_version).order_by('-pk').first()
    if latest_term and latest_term.outcome == 'needs_review':
        raise ValidationError('The existing participation requires academic review before placement.')
    if source.semester.is_active and any(p.ended_at is None for p in placements):
        raise ValidationError(f'The student already belongs to {source.name}. Resolve that placement first.')
    # A recorded successful normal continuation establishes its prior course.
    if phase_for(source) == 'capstone_2':
        from .capstone_lifecycle import project_outcome
        if project_outcome(source)[0] == 'completed':
            raise ValidationError('The existing Capstone project is already completed.')
        if inherited_stage_ids(source):
            return {'kind': 'recorded', 'participation_id': row.pk, 'source_team_id': source.pk}
    if row.origin == 'external_continuation' and CapstoneRosterConfirmation.objects.filter(
            member_evidence__contains=[{'participation_id': row.pk}]).exists():
        return {'kind': 'recorded', 'participation_id': row.pk, 'source_team_id': source.pk}
    requirements = requirements_for(source)
    evidenced = [(i, latest_stage_assessment(source, r['id'])) for i, r in enumerate(requirements)]
    progress_ids = set(source.stage_progress.filter(project_version=source.project_version)
        .exclude(status='locked').values_list('defense_stage_id', flat=True))
    used = [(i, grade) for i, grade in evidenced if grade is not None or requirements[i]['id'] in progress_ids]
    if not used or any(not stage_cleared(source, r) for r in requirements[:max(i for i, _ in used)+1]):
        raise ValidationError('The recorded Capstone 1 assessment or clearance is incomplete.')
    from defense.scheduler.models import DefenseSchedule
    if DefenseSchedule.objects.filter(team=source, project_version=source.project_version, status='scheduled').exists():
        raise ValidationError('The source project still has an open defense schedule.')
    return {'kind': 'recorded', 'participation_id': row.pk, 'source_team_id': source.pk}


def validate_confirmation(actor, term, student_ids, confirmation, *, target=None, lock=False):
    if not user_is_admin(actor):
        raise PermissionDenied('Only administrators can confirm Capstone 2 eligibility.')
    if not term.is_active or term.label != Semester.FIRST:
        raise ValidationError({'capstone2_confirmation': 'Choose the active Capstone 2 semester.'})
    if not confirmation or confirmation.get('confirmed') is not True:
        raise ValidationError({'capstone2_confirmation': 'Confirm that all selected members passed Capstone 1.'})
    if target:
        from .participation import require_open
        require_open(target)
    people = {p.pk: p for p in get_user_model().objects.filter(pk__in=student_ids, is_active=True, role='student')}
    if set(people) != set(student_ids):
        raise ValidationError({'member_ids': 'All members must be active student accounts.'})
    evidence, errors = [], []
    for student_id in sorted(student_ids):
        person = people[student_id]
        try:
            evidence.append({'student_id': student_id, **evidence_for(student_id, target=target)})
        except (ValidationError, ModelValidationError) as exc:
            detail = exc.detail if isinstance(exc, ValidationError) else exc.messages
            message = ' '.join(str(value) for value in detail) if isinstance(detail, (list, tuple)) else str(detail)
            errors.append(f'{person.get_full_name() or person.username} ({person.username}): {message}')
    if errors:
        raise ValidationError({'member_ids': errors})
    reference = (confirmation.get('reference') or '').strip()
    if any(item['kind'] == 'external' for item in evidence) and not reference:
        raise ValidationError({'capstone2_confirmation': 'Enter a school record reference for members with missing prior results.'})
    if len(reference) > 500:
        raise ValidationError({'capstone2_confirmation': 'The school record reference must be at most 500 characters.'})
    from .roster_enrollment import require_roster_enrollment
    require_roster_enrollment(student_ids, term, lock=lock)
    return evidence


def confirm(team, student_ids, actor, confirmation, payload):
    """Called inside the serializer's period/student/team-locked transaction."""
    evidence = validate_confirmation(actor, team.semester, student_ids, confirmation, target=team, lock=True)
    now = timezone.now()
    Placement.objects.filter(team=team, ended_at__isnull=True).exclude(
        participation__student_id__in=student_ids).update(ended_at=now)
    for item in evidence:
        row = Participation.objects.filter(pk=item.get('participation_id')).first()
        if row is None:
            previous = Participation.objects.filter(student_id=item['student_id']).order_by('-number').first()
            row = Participation.objects.create(student_id=item['student_id'], intake_semester=None,
                number=(previous.number+1 if previous else 1), previous=previous,
                origin='external_continuation', history_complete=False, confirmed_by=actor)
        # An old placement is closed only as part of the validated atomic write.
        Placement.objects.filter(participation=row, ended_at__isnull=True).exclude(team=team).update(ended_at=now)
        Placement.objects.get_or_create(participation=row, team=team, ended_at=None,
            defaults={'snapshot': {'team_name': team.name, 'project_title': team.project_title,
                                  'semester_id': team.semester_id, 'qualification_source': item['kind']}})
        item['participation_id'] = row.pk
    CapstoneRosterConfirmation.objects.create(request_id=confirmation['request_id'],
        fingerprint=fingerprint(payload), team=team, semester=team.semester, actor=actor,
        reference=(confirmation.get('reference') or '').strip(), member_evidence=evidence)
    from .capstone_lifecycle import capture_participation
    capture_participation(team)
    from .history_events import record_team_event
    record_team_event(team, 'capstone.eligibility_confirmed', actor=actor,
        values={'reference': confirmation.get('reference', ''), 'member_evidence': evidence})


def reconcile_source(data, actor, confirmation, payload):
    """Reuse an exact, settled source project instead of manufacturing its copy."""
    from .participation import roster_ids, intake_for
    evidence = validate_confirmation(actor, data['semester'], set(data['member_ids']), confirmation)
    ids = {item.get('source_team_id') for item in evidence}
    if len(ids) != 1 or None in ids:
        return None
    source = StudentTeam.objects.select_for_update().select_related('semester__school_year').get(pk=ids.pop())
    if roster_ids(source) != set(data['member_ids']) or source.project_title.strip().casefold() != data['project_title'].strip().casefold():
        return None
    from .capstone_lifecycle import capture_participation, requirements_for, configured_requirements, stage_cleared
    old_requirements = requirements_for(source)
    cleared = [item['id'] for item in old_requirements if stage_cleared(source, item)]
    previous = capture_participation(source, requirements=old_requirements)
    previous.closed_at = timezone.now()
    previous.save(update_fields=['closed_at', 'updated_at'])
    old_adviser_id = source.adviser_id
    source.intake_semester = intake_for(source)
    for field in ('name', 'project_title', 'section', 'leader', 'adviser', 'year_level', 'level', 'semester'):
        setattr(source, field, data[field])
    source.capstone_registration_semester = source.semester
    source.ready_for_stage = None
    current = configured_requirements(source.semester)
    source.current_defense_stage = next((r['label'] for r in current if r['id'] not in cleared), None)
    source.save()
    # The old snapshot was captured before changing current leader flags.
    source.memberships.update(is_leader=False)
    source.memberships.filter(student_id=source.leader_id).update(is_leader=True)
    combined = {r['id']: r for r in old_requirements + current}
    target = capture_participation(source, requirements=list(combined.values()))
    target.snapshot['inherited_stage_ids'] = cleared
    target.save(update_fields=['snapshot', 'updated_at'])
    confirm(source, set(data['member_ids']), actor, confirmation, payload)
    from .adviser_assignments import record_team_adviser_change
    record_team_adviser_change(source, old_adviser_id, source.adviser, assigned_by=actor)
    return source
