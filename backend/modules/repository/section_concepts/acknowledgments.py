"""Shared understanding is separate from paper acceptance and team endorsement."""
from hashlib import sha256
import json

from django.db import transaction
from defensys_backend.read_projection import read_memoize

from .models import SectionConceptAcknowledgment, SectionConceptPaper


@read_memoize
def pit_instructors(project):
    from user_management.models import SectionInstructorAssignment
    return SectionInstructorAssignment.objects.filter(semester_id=project.section.semester_id,
        section=project.section.section, year_level=project.section.year_level, is_active=True,
        faculty__is_active=True).values_list('faculty_id', flat=True).distinct()


@read_memoize
def pit_reviewer_id(project):
    ids = list(pit_instructors(project))
    return ids[0] if len(ids) == 1 else project.reviewer_id if project.reviewer_id in ids else None


def required_faculty_id(team, project):
    return pit_reviewer_id(project) if project.pit_event_config_id else team.adviser_id


def can_acknowledge(actor, project):
    from .services import active_links
    if not actor or getattr(actor, 'role', '') != 'faculty' or not actor.is_active:
        return False
    if project.pit_event_config_id:
        return actor.pk == pit_reviewer_id(project)
    return active_links(project).filter(team__adviser=actor).exists()


@read_memoize(copy=True)
def version_snapshot(round):
    # Status/reviewer changes and roster additions do not change the content read.
    return {'round_id': round.pk,
        'systems': list(round.systems.order_by('key').values('id', 'key', 'title')),
        'papers': list(SectionConceptPaper.objects.filter(concept__round=round, is_current=True)
                      .order_by('concept__key').values('id', 'concept_id', 'revision'))}


def fingerprint(state):
    return sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()


def available(state):
    return (bool(state['systems']) and all(s['title'].strip() for s in state['systems'])
        and len(state['papers']) == len(state['systems'])
        and {p['concept_id'] for p in state['papers']} == {s['id'] for s in state['systems']})


@read_memoize
def acknowledged(round, faculty_id, *, state=None):
    state = state or version_snapshot(round)
    if not faculty_id or not available(state):
        return False
    if round.acknowledgments.filter(faculty_id=faculty_id, fingerprint=fingerprint(state)).exists():
        return True
    # The assigned reviewer has already read these exact papers by accepting them.
    # Confirming names or another faculty member's acceptance alone is insufficient.
    return (not round.systems.exclude(confirmed=True).exists()
        and SectionConceptPaper.objects.filter(pk__in=[p['id'] for p in state['papers']],
            reviewed_by_id=faculty_id, status='accepted').count() == len(state['systems']))


def summary(round, *, team=None, actor=None):
    state = version_snapshot(round)
    faculty_id = required_faculty_id(team, round.project) if team else getattr(actor, 'pk', None)
    valid = acknowledged(round, faculty_id, state=state)
    required = True
    if team:
        current = round.module_rounds.filter(team=team).order_by('-number', '-pk').first()
        required = not (current and current.schedule_id and current.schedule.status != 'cancelled')
    authorized = can_acknowledge(actor, round.project)
    return {'acknowledged': valid, 'acknowledgment_required': required,
        'can_review_shared_context': authorized,
        'acknowledgment_faculty_id': faculty_id,
        'can_acknowledge': bool(available(state) and authorized and not valid and required),
        'papers_available': available(state)}


@transaction.atomic
def acknowledge(project, actor):
    from .services import require_active, locked_round, audit
    from django.core.exceptions import ValidationError
    require_active(project)
    round = locked_round(project)
    if not can_acknowledge(actor, project):
        raise PermissionError('Only this section’s assigned instructor or a linked team’s adviser can acknowledge its shared proposals.')
    state = version_snapshot(round)
    if not available(state):
        raise ValidationError('All current shared proposal titles and papers must be available before acknowledgment.')
    row, created = SectionConceptAcknowledgment.objects.get_or_create(round=round, faculty=actor,
        fingerprint=fingerprint(state), defaults={'snapshot': state})
    if created:
        audit(actor, 'shared_context_acknowledged', row, round_id=round.pk, snapshot=state)
    return row
