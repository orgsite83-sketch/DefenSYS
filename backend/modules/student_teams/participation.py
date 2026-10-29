"""Student intake identity and placement. Reads never allocate participation numbers.

Enrollment is a separate record. The only new-intake writer is confirm_roster,
called transactionally by the roster serializer after permanent IDs are resolved.
"""
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DomainValidationError
from django.db import transaction
from django.db.models import Max, Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from academic_period_management.models import Semester
from .models import StudentTeam, StudentCapstoneParticipation as Participation, StudentCapstonePlacement as Placement


def term_key(term):
    return term.school_year.label, {Semester.FIRST: 1, Semester.SECOND: 2, Semester.SUMMER: 3}[term.label]


def roster_ids(team):
    return set(team.memberships.values_list('student_id', flat=True)) | {team.leader_id}


def intake_for(team):
    if team.intake_semester_id:
        return team.intake_semester
    if team.participation_review_reason:
        return None
    if team.semester.label == Semester.SECOND:
        return team.semester
    return Semester.objects.filter(label=Semester.SECOND,
        team_participations__team=team, team_participations__is_extended=False
    ).select_related('school_year').order_by('school_year__label', 'pk').first()


def failure_for(team):
    """Latest official stage evidence, never a low score or an older failed hearing."""
    from .capstone_lifecycle import latest_stage_assessment
    from grading.grades.models import TeamGrade
    stages = TeamGrade.all_objects.filter(team=team, project_version=team.project_version,
        scope='capstone').values_list('defense_stage_id', flat=True).distinct()
    for stage_id in stages:
        grade = latest_stage_assessment(team, stage_id)
        if grade and grade.status == TeamGrade.STATUS_PUBLISHED and grade.result == 'failed':
            return grade
    return None


def closed_failure(team):
    return bool(team.is_capstone and (failure_for(team) or
        team.term_participations.filter(project_version=team.project_version, outcome='failed', closed_at__isnull=False).exists()))


def require_open(team):
    if team.is_capstone and (team.participation_review_reason or closed_failure(team)):
        raise DomainValidationError('This Capstone participation is closed or requires historical review. Returning students must join a new Capstone 1 intake.')


def previous_evidence(student_id, *, exclude_team=None):
    """Reliable pre-ledger evidence also protects old fixtures/imports, without writing."""
    teams = StudentTeam.objects.filter(level__icontains='Capstone').filter(
        Q(leader_id=student_id) | Q(memberships__student_id=student_id)
    ).exclude(pk=exclude_team).select_related('semester__school_year', 'intake_semester__school_year').distinct()
    return list(teams)


def validate_roster(student_ids, term, *, team=None):
    """Shared by preview and commit. No client-supplied sequence or override."""
    students = {s.pk: s for s in get_user_model().objects.filter(pk__in=student_ids, role='student', is_active=True)}
    if set(students) != set(student_ids):
        raise ValidationError({'member_ids': 'All members must be active student accounts.'})
    if team:
        try:
            require_open(team)
        except DomainValidationError as exc:
            raise ValidationError({'member_ids': exc.messages}) from exc
    errors = []
    for student_id in sorted(student_ids):
        person = students[student_id]
        label = f'{person.get_full_name() or person.username} ({person.username})'
        participation = Participation.objects.filter(student_id=student_id).select_related(
            'intake_semester__school_year').order_by('-number').first()
        current_intake = intake_for(team) if team else None
        if participation and current_intake and participation.intake_semester_id == current_intake.pk:
            if participation.state != Participation.ACTIVE:
                errors.append(f'{label}: this participation is {participation.get_state_display()}. Join a new Capstone 1 intake.')
                continue
            placement = participation.placements.filter(ended_at__isnull=True).exclude(team=team).first()
            if placement:
                errors.append(f'{label} already belongs to another team in this intake.')
            continue
        if term.label != Semester.SECOND:
            errors.append(f'{label} cannot start a Capstone participation in Capstone 2. Include the student in a new Capstone 1 intake roster.')
            continue
        if participation:
            if participation.intake_semester_id == term.pk:
                if participation.state != Participation.ACTIVE:
                    errors.append(f'{label}: a finalized participation cannot be reopened or transferred in the same intake.')
                elif participation.placements.filter(ended_at__isnull=True).exclude(team=team).exists():
                    errors.append(f'{label} already belongs to another team in this intake.')
            elif participation.state != Participation.FAILED or term_key(term) <= term_key(participation.intake_semester):
                errors.append(f'{label}: the previous participation is not a finalized Failed participation eligible for this new intake.')
            elif any(term_key(p.team.semester) >= term_key(term) for p in participation.placements.select_related('team__semester__school_year')):
                errors.append(f'{label}: this intake must be after the previous participation ended.')
        else:
            for old in previous_evidence(student_id, exclude_team=team.pk if team else None):
                old_intake = intake_for(old)
                if not old_intake or term_key(term) <= term_key(old_intake) or not closed_failure(old):
                    errors.append(f'{label}: previous Capstone history requires review before placement in this intake.')
                    break
    if errors:
        raise ValidationError({'member_ids': errors, 'code': 'capstone_placement_ineligible'})


@transaction.atomic
def confirm_roster(team, student_ids, *, actor=None):
    if not team.is_capstone:
        return
    # Period -> student -> team is the shared lock order used by activation/import.
    list(Semester.objects.select_for_update().order_by('pk'))
    list(get_user_model().objects.select_for_update().filter(pk__in=student_ids).order_by('pk'))
    team = StudentTeam.objects.select_for_update(of=('self',)).select_related('semester__school_year', 'intake_semester__school_year').get(pk=team.pk)
    validate_roster(student_ids, team.semester, team=team)
    intake = intake_for(team)
    if not intake:
        raise ValidationError('The original Capstone intake requires review.')
    if not team.intake_semester_id:
        team.intake_semester = intake
        team.save(update_fields=['intake_semester', 'updated_at'])
    now = timezone.now()
    Placement.objects.filter(team=team, ended_at__isnull=True).exclude(
        participation__student_id__in=student_ids).update(ended_at=now)
    for student_id in sorted(student_ids):
        participation = Participation.objects.filter(student_id=student_id, intake_semester=intake).first()
        if not participation:
            # Bootstrap only an evidenced prior intake, never an authorization or hearing count.
            for old in sorted(previous_evidence(student_id, exclude_team=team.pk), key=lambda t: term_key(t.semester)):
                prior_intake = intake_for(old)
                if prior_intake and term_key(prior_intake) < term_key(intake) and closed_failure(old):
                    prior, created = Participation.objects.get_or_create(student_id=student_id, intake_semester=prior_intake,
                        defaults={'number': (Participation.objects.filter(student_id=student_id).aggregate(n=Max('number'))['n'] or 0) + 1,
                                  'state': Participation.FAILED})
                    if created:
                        Placement.objects.create(participation=prior, team=old, ended_at=now,
                            snapshot={'team_name': old.name, 'project_title': old.project_title, 'semester_id': old.semester_id})
            previous = Participation.objects.filter(student_id=student_id).order_by('-number').first()
            participation = Participation.objects.create(student_id=student_id, intake_semester=intake,
                number=previous.number + 1 if previous else 1, previous=previous, confirmed_by=actor)
        Placement.objects.get_or_create(participation=participation, team=team, ended_at=None,
            defaults={'snapshot': {'team_name': team.name, 'project_title': team.project_title, 'semester_id': team.semester_id}})


@transaction.atomic
def finalize_failed(team, actor=None):
    """Official failure closes the current participation; no recovery grant can reopen it."""
    from .capstone_lifecycle import capture_participation
    row = team.term_participations.filter(semester=team.semester).first()
    if not row or not row.closed_at:
        row = capture_participation(team)
        row.outcome, row.closed_at = 'failed', timezone.now()
        row.save(update_fields=['outcome', 'closed_at', 'updated_at'])
    close_placements(team, Participation.FAILED)


def close_placements(team, state):
    placements = Placement.objects.filter(team=team, ended_at__isnull=True)
    ids = list(placements.values_list('participation_id', flat=True))
    Participation.objects.filter(pk__in=ids).update(state=state)
    placements.update(ended_at=timezone.now(), snapshot={'team_name': team.name,
        'project_title': team.project_title, 'semester_id': team.semester_id})


def student_history(student_id):
    rows = Participation.objects.filter(student_id=student_id).select_related('intake_semester__school_year').prefetch_related('placements__team__semester__school_year')
    return [{'id': row.pk, 'number': row.number, 'state': row.state,
        'intake_semester_id': row.intake_semester_id, 'intake': row.intake_semester.display_name,
        'placements': [{'team_id': p.team_id, 'team_name': p.team.name if row.state == 'active' and not p.ended_at else p.snapshot.get('team_name', p.team.name),
            'project_title': p.snapshot.get('project_title', p.team.project_title),
            'ended_at': p.ended_at.isoformat() if p.ended_at else None} for p in row.placements.all()]} for row in rows]


def member_participation(team, student_id):
    row = Participation.objects.filter(student_id=student_id, placements__team=team).order_by('-number').first()
    return {'number': row.number if row else None, 'state': row.state if row else 'needs_review',
            'intake_semester_id': row.intake_semester_id if row else None}


def roster_preview(student_ids, term):
    """Proposed numbers for review only; enrollment/import preview allocates nothing."""
    result = []
    students = {s.pk: s for s in get_user_model().objects.filter(pk__in=student_ids)}
    for student_id in sorted(student_ids):
        latest = Participation.objects.filter(student_id=student_id).order_by('-number').first()
        same = bool(latest and latest.intake_semester_id == term.pk)
        if latest:
            number = latest.number if same else latest.number + 1
        else:
            intakes = {intake_for(team).pk for team in previous_evidence(student_id)
                if intake_for(team) and closed_failure(team) and term_key(intake_for(team)) < term_key(term)}
            number = len(intakes) + 1
        person = students[student_id]
        result.append({'student_id': student_id, 'name': person.get_full_name() or person.username,
            'username': person.username, 'number': number, 'returning': number > 1,
            'already_confirmed': same, 'proposed': not same})
    return result


def existing_roster(student_ids, term, name, level):
    team = StudentTeam.objects.filter(semester=term, name=name, level=level).first()
    return team if team and roster_ids(team) == set(student_ids) else None


def reconcile_enrollment_sections(term, student_ids, actor=None, applied_defaults=None):
    from .continuation_sections import reconcile_sections
    reconcile_sections(term, student_ids, actor=actor, applied_defaults=applied_defaults)
