"""Authoritative Capstone continuity and preserved source-term evidence.

Calendar changes trigger review; official assessment evidence supplies outcomes.
Read projections never create rows. All writes are called inside transactions.
"""
from copy import copy
from hashlib import sha256
import json

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from defensys_backend.read_projection import read_memoize

from academic_period_management.models import Semester
from .models import StudentTeam, TeamStageProgress, TeamTermParticipation



def year_after(label):
    start, end = map(int, label.split('-'))
    return f'{start + 1}-{end + 1}'


def term_key(term):
    return (term.school_year.label, {Semester.FIRST: 1, Semester.SECOND: 2, Semester.SUMMER: 3}[term.label])


def transition_kind(source, target):
    if not source:
        return 'initial'
    if source.pk == target.pk:
        return 'same'
    if source.label == Semester.SECOND and target.label == Semester.FIRST and target.school_year.label == year_after(source.school_year.label):
        return 'continue'
    if source.label == Semester.FIRST and target.label == Semester.SECOND and target.school_year_id == source.school_year_id:
        return 'close_cycle'
    return 'exceptional'


@read_memoize(copy=True)
def configured_requirements():
    from defense.stages.models import DefenseStage
    from repository.deliverables.services import get_deliverable_definitions
    return [{'id': stage.pk, 'label': stage.label, 'order': stage.display_order,
             'presentation_only': False,
             'definitions': get_deliverable_definitions(stage.label),
             'updated_at': stage.updated_at.isoformat()}
            for stage in DefenseStage.objects.filter(is_active=True).order_by('display_order', 'id')]


@read_memoize(copy=True)
def requirements_for(team):
    """Freeze historical requirements; reconcile unstarted stages of open projects."""
    recorded = getattr(team, '_recorded_term', None)
    if recorded:
        return recorded.requirements
    participation = team.term_participations.filter(project_version=team.project_version).order_by('-semester__school_year__label', '-id').first()
    captured = participation.requirements if participation else []
    if captured and participation.closed_at:
        return captured
    current = configured_requirements()
    if not captured:
        return current
    used = set(TeamStageProgress.all_objects.filter(team=team, project_version=team.project_version)
               .exclude(status=TeamStageProgress.STATUS_LOCKED).values_list('defense_stage_id', flat=True))
    from grading.grades.models import TeamGrade
    used.update(TeamGrade.all_objects.filter(team=team, project_version=team.project_version).filter(
        Q(status='published') | ~Q(verdict='') | Q(schedule__isnull=False) | Q(panel_score__isnull=False)
    ).values_list('defense_stage_id', flat=True))
    by_id = {item['id']: item for item in current}
    result = [item if item['id'] in used else by_id.get(item['id'], item) for item in captured
              if item['id'] in used or item['id'] in by_id]
    known = {item['id'] for item in result}
    return sorted(result + [item for item in current if item['id'] not in known], key=lambda item: item['order'])


@read_memoize(copy=True)
def requirement_for_label(team, label):
    from defense.stages.models import DefenseStage
    stage_id = DefenseStage.objects.filter(label=label).values_list('pk', flat=True).first()
    return next((item for item in requirements_for(team)
                 if item['id'] == stage_id or item['label'] == label), None)










def evidence_team(team, grade, requirement=None):
    """Explicit source context without changing the team's database semester."""
    source = copy(team)
    source._state = copy(team._state)
    source._state.fields_cache = dict(team._state.fields_cache)
    source.semester = grade.semester
    source.project_version = grade.project_version
    source._assessment_semester_id = grade.semester_id
    source._prefetched_objects_cache = {}
    participation = team.term_participations.filter(semester=grade.semester).first()
    if participation:
        for field in ('name', 'project_title', 'level', 'year_level', 'section', 'adviser_id'):
            if field in participation.snapshot:
                setattr(source, field, participation.snapshot[field])
    if requirement:
        source._capstone_requirement = requirement
        source._projection_context = requirement
    return source


def latest_stage_assessment(team, stage_id):
    from grading.grades.models import TeamGrade
    grades = list(TeamGrade.all_objects.filter(team=team, project_version=team.project_version,
        scope='capstone', defense_stage_id=stage_id).select_related('semester__school_year', 'schedule', 'team', 'defense_stage'))
    # A new term's unscheduled empty row is a placeholder, not another attempt.
    substantive = [g for g in grades if g.verdict or g.status == 'published'
        or any(value is not None for value in (g.panel_score, g.adviser_score, g.peer_score))
        or (g.schedule_id and g.schedule.status != 'cancelled')]
    return max(substantive or grades, key=lambda g: (term_key(g.semester), g.updated_at, g.pk), default=None)


def stage_cleared(team, requirement, grade=None):
    from grading.grades.defense_workflow import passed_and_cleared, legacy_finalized_pass
    from repository.deliverables.services import required_complete, post_deliverables_complete
    grade = grade or latest_stage_assessment(team, requirement['id'])
    if not grade or grade.status != grade.STATUS_PUBLISHED or not grade.is_complete:
        return False
    source = evidence_team(team, grade, requirement)
    grade.team = source
    if not (passed_and_cleared(grade) or legacy_finalized_pass(grade)):
        return False
    label = grade.stage_label or grade.defense_stage.label
    if not required_complete(source, label):
        return False
    return post_deliverables_complete(source, label)


def project_outcome(team, requirements=None):
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    requirements = requirements if requirements is not None else requirements_for(team)
    if not requirements:
        return 'needs_review', None, 'No reliable configured stage requirements are available.'
    if DefenseSchedule.objects.filter(team=team, project_version=team.project_version,
            scope='capstone', status=DefenseSchedule.STATUS_SCHEDULED).exists():
        return 'needs_review', None, 'A defense attempt is still open.'
    incomplete, failures = [], []
    for requirement in requirements:
        grade = latest_stage_assessment(team, requirement['id'])
        if grade and grade.status == TeamGrade.STATUS_PUBLISHED and (grade.verdict == TeamGrade.VERDICT_FAILED or grade.closed_as_failed):
            failures.append(grade)
        elif not stage_cleared(team, requirement, grade):
            incomplete.append(requirement['label'])
    if failures:
        grade = max(failures, key=lambda g: (term_key(g.semester), g.updated_at, g.pk))
        return 'failed', grade, 'Official Failed assessment recorded.'
    if incomplete:
        return 'needs_review', None, 'Required grading or clearance is incomplete: ' + ', '.join(incomplete)
    return 'completed', None, 'All applicable stages are passed and cleared.'


def team_snapshot(team):
    from .serializers import display_name
    members = [{'student_id': m.student_id, 'username': m.student.username,
                'name': display_name(m.student), 'is_leader': m.is_leader}
               for m in team.memberships.select_related('student').all()]
    return {'id': team.pk, 'name': team.name, 'project_title': team.project_title,
            'project_version': team.project_version, 'project_pending': team.project_pending,
            'setup_pending': team.setup_pending, 'level': team.level, 'year_level': team.year_level,
            'section': team.section, 'semester_id': team.semester_id, 'semester': team.semester.label,
            'school_year': team.semester.school_year.label, 'display_semester': team.semester.display_name,
            'leader_id': team.leader_id, 'leader_name': display_name(team.leader), 'leader_username': team.leader.username,
            'adviser_id': team.adviser_id, 'adviser_name': display_name(team.adviser),
            'adviser_username': team.adviser.username if team.adviser else None,
            'member_ids': [m['student_id'] for m in members], 'members': members, 'member_count': len(members),
            'deliverable_count': team.deliverable_submissions.count(),
            'status': team.status, 'capstone_phase': team.capstone_phase,
            'current_defense_stage': team.current_defense_stage, 'ready_for_stage': team.ready_for_stage,
            'is_capstone': True, 'created_at': team.created_at.isoformat(), 'updated_at': team.updated_at.isoformat()}


@transaction.atomic
def capture_participation(team, *, requirements=None):
    current = StudentTeam.objects.select_for_update().only('semester_id', 'project_version').get(pk=team.pk)
    if (current.semester_id, current.project_version) != (team.semester_id, team.project_version):
        raise ValidationError('The team term or project changed. Refresh before continuing.')
    row, _ = TeamTermParticipation.objects.select_for_update().get_or_create(team=team, semester=team.semester,
        defaults={'project_version': team.project_version})
    if row.closed_at:
        raise ValidationError('This term participation is closed. Use the historical correction process.')
    row.project_version = team.project_version
    row.is_extended = False
    row.requirements = requirements if requirements is not None else requirements_for(team)
    row.snapshot = team_snapshot(team)
    row.save()
    return row


def historical_payload(row):
    from grading.grades.models import TeamGrade
    payload = dict(row.snapshot)
    payload.update({'id': row.team_id, 'semester_id': row.semester_id, 'semester': row.semester.label,
        'school_year': row.semester.school_year.label, 'display_semester': row.semester.display_name,
        'project_version': row.project_version, 'term_status': 'historical', 'is_editable': False,
        'participation_id': row.pk, 'capstone_outcome': row.outcome,
        'status': {'completed': 'Completed', 'failed': 'Failed', 'needs_review': 'Needs review'}.get(row.outcome, payload.get('status', 'Pending')),
        'defense_context': {'is_pit': False, 'current_stage': payload.get('current_defense_stage'),
                            'stage_status': row.outcome, 'deliverable_count': payload.get('deliverable_count', 0)},
        'stage_requirements': row.requirements,
        'assessments': list(TeamGrade.all_objects.filter(team_id=row.team_id, semester_id=row.semester_id)
            .order_by('project_version', 'id').values('id', 'project_version', 'project_title_snapshot',
                'defense_stage_id', 'stage_label', 'status', 'verdict', 'final_grade'))})
    return payload


def build_capstone_review(source, target):
    """Preview normal movement only. Missing future enrollment is informational."""
    from grading.grades.models import TeamGrade
    from user_management.academic_records.models import StudentAcademicRecord
    from .participation import failure_for, intake_for, roster_ids
    from django.contrib.auth import get_user_model
    kind = transition_kind(source, target)
    teams = StudentTeam.objects.filter(semester=source, level__icontains='Capstone') if source else StudentTeam.objects.none()
    rows, fingerprints = [], []
    for team in teams.select_related('semester__school_year', 'intake_semester__school_year', 'leader', 'adviser').order_by('name', 'pk'):
        requirements = requirements_for(team)
        roster = roster_ids(team)
        enrollment = list(StudentAcademicRecord.objects.filter(semester_id=target.pk, student_id__in=roster).order_by('pk').values('student_id', 'year_level', 'section')) if target.pk else []
        pending_enrollment = len(enrollment) != len(roster)
        destination, can_include, outcome = 'needs_review', False, 'needs_review'
        reason = team.participation_review_reason
        failed = failure_for(team)
        prior = team.term_participations.filter(project_version=team.project_version, closed_at__isnull=False, outcome='failed').exists()
        if failed or prior:
            destination, outcome = 'failed_history', 'failed'
            reason = 'Finalized Failed. Returning students join a new Capstone 1 intake.'
        elif reason:
            pass
        elif kind == 'continue':
            intake = intake_for(team)
            grades = list(TeamGrade.all_objects.filter(team=team, project_version=team.project_version,
                semester=source, scope='capstone').filter(Q(schedule__isnull=False) | Q(status='published') |
                ~Q(verdict='') | Q(panel_score__isnull=False)).select_related('defense_stage'))
            if not intake or intake.pk != source.pk:
                reason = 'The original intake and participation require review.'
            elif not requirements or not grades:
                reason = 'No reliable completed source-term assessment is recorded.'
            else:
                stage_ids = {g.defense_stage_id for g in grades}
                applicable = [r for r in requirements if r['id'] in stage_ids]
                open_hearing = team.defense_schedules.filter(project_version=team.project_version, status='scheduled').exists() if hasattr(team, 'defense_schedules') else False
                from defense.scheduler.models import DefenseSchedule
                open_hearing = open_hearing or DefenseSchedule.objects.filter(team=team, project_version=team.project_version, status='scheduled', scope='capstone').exists()
                unfinished = [r['label'] for r in applicable if not stage_cleared(team, r)]
                if open_hearing or unfinished or len(applicable) != len(stage_ids):
                    reason = 'Source-term assessment or clearance is incomplete' + (': ' + ', '.join(unfinished) if unfinished else '.')
                elif set(get_user_model().objects.filter(pk__in=roster, is_active=True, role='student').values_list('pk', flat=True)) != roster:
                    reason = 'A continuing member has an inactive or invalid student account.'
                elif any(r['year_level'] != '4th Year' for r in enrollment):
                    reason = 'An existing destination enrollment does not match fourth-year continuation.'
                elif len({r['section'] for r in enrollment if r['section']}) > 1:
                    reason = 'Destination enrollment sections conflict. Review the official roster.'
                elif target.pk and StudentTeam.objects.filter(semester=target, level__icontains='Capstone').exclude(pk=team.pk).filter(Q(leader_id__in=roster) | Q(memberships__student_id__in=roster)).exists():
                    reason = 'A member already belongs to another Capstone team in the destination term.'
                else:
                    destination, can_include, outcome = 'continue', True, 'open'
                    reason = ''
        elif kind == 'close_cycle':
            outcome, _, reason = project_outcome(team, requirements)
            destination = 'history' if outcome == 'completed' else 'needs_review'
        else:
            reason = 'This switch does not provide normal consecutive-term continuation.'
        row = {'team_id': team.pk, 'name': team.name, 'project_title': team.project_title,
            'project_version': team.project_version, 'outcome': outcome, 'destination': destination,
            'can_include': can_include, 'pending_enrollment': pending_enrollment, 'reason': reason}
        rows.append(row)
        fingerprints.append({'team': team_snapshot(team), 'row': row, 'requirements': requirements,
            'enrollment': enrollment,
            'students': list(get_user_model().objects.filter(pk__in=roster).order_by('pk').values('id', 'is_active', 'role')),
            'grades': list(TeamGrade.all_objects.filter(team=team, project_version=team.project_version).order_by('pk').values('id', 'semester_id', 'status', 'verdict', 'updated_at', 'outcome_metadata'))})
    counts = {key: sum(r['destination'] == key for r in rows) for key in ('history', 'failed_history', 'continue', 'needs_review')}
    revision = sha256(json.dumps({'source': source.pk if source else None,
        'target': [target.school_year_id, target.label, target.starts_on, target.ends_on],
        'kind': kind, 'teams': fingerprints}, sort_keys=True, default=str).encode()).hexdigest()
    return {'kind': kind, 'teams': rows, 'counts': counts, 'total': len(rows), 'revision': revision,
            'requires_review': bool(rows)}








def apply_capstone_transition(source, target, review, *, actor, log):
    """Activate only eligible normal continuation; failed/closed work stays historical."""
    from .models import StudentCapstoneParticipation, StudentCapstonePlacement
    from .participation import confirm_roster, roster_ids
    if review['kind'] not in ('continue', 'close_cycle'):
        return []
    applied = []
    for item in review['teams']:
        team = StudentTeam.objects.select_for_update(of=('self',)).select_related('semester__school_year', 'intake_semester__school_year', 'leader', 'adviser').get(pk=item['team_id'])
        requirements = requirements_for(team)
        old = team.term_participations.filter(semester=source).first()
        if not old or not old.closed_at:
            old = capture_participation(team, requirements=requirements)
            old.outcome, old.closed_at, old.transition = item['outcome'], timezone.now(), log
            old.save()
        if item['can_include']:
            if team.term_participations.filter(semester=target).exists():
                raise ValidationError('This team already has destination-term participation. Refresh the preview.')
            confirm_roster(team, roster_ids(team), actor=actor)
            team.refresh_from_db()
            team.semester = target
            team.level, team.year_level = StudentTeam.LEVEL_4_CAPSTONE, '4th Year'
            team.capstone_phase = StudentTeam.PHASE_ACTIVE
            next_stage = next((r for r in requirements if not stage_cleared(team, r)), None)
            from defense.stages.models import DefenseStage
            team.current_defense_stage = (DefenseStage.objects.filter(pk=next_stage['id']).values_list('label', flat=True).first() or next_stage['label']) if next_stage else None
            team.ready_for_stage = None
            team.save()
            new = capture_participation(team, requirements=requirements)
            new.transition = log
            new.save(update_fields=['transition', 'updated_at'])
            applied.append(team.pk)
        elif item['outcome'] in ('failed', 'completed'):
            ids = StudentCapstonePlacement.objects.filter(team=team).values('participation_id')
            StudentCapstoneParticipation.objects.filter(pk__in=ids).update(state=item['outcome'])
    return applied










def teams_in_recorded_term(queryset, semester):
    return queryset.filter(Q(semester=semester) | Q(term_participations__semester=semester)).distinct()


def filter_recorded_team_field(queryset, semester, field, value, *, lookup='exact'):
    rows = TeamTermParticipation.objects.filter(semester=semester, closed_at__isnull=False)
    matching = rows.filter(**{f'snapshot__{field}__{lookup}': value}).values('team_id')
    return queryset.filter(Q(pk__in=matching) |
        (Q(**{f'{field}__{lookup}': value}) & ~Q(pk__in=rows.values('team_id'))))


def recorded_team(team, semester):
    row = team.term_participations.filter(semester=semester, closed_at__isnull=False).first()
    if not row:
        return team
    source = copy(team)
    source._state = copy(team._state)
    source._state.fields_cache = dict(team._state.fields_cache)
    for field in ('name', 'project_title', 'level', 'year_level', 'section', 'leader_id', 'adviser_id',
                  'status', 'capstone_phase', 'current_defense_stage', 'ready_for_stage'):
        if field in row.snapshot:
            setattr(source, field, row.snapshot[field])
    source.semester, source.project_version = semester, row.project_version
    source._recorded_term = row
    source._assessment_semester_id = semester.pk
    source._projection_context = row.requirements
    return source
