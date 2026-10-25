"""Authoritative Capstone continuity, completion, and extension decisions.

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
from .models import (CapstoneJourney, StudentTeam, TeamMembership,
                     TeamRecoveryAuthorization, TeamStageProgress, TeamTermParticipation)

EXTENSION_POLICY = 'next_two_regular_semesters_v1'


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
    """Keep older Extended requirements; append published stages to an open normal cohort."""
    recorded = getattr(team, '_recorded_term', None)
    if recorded:
        return recorded.requirements
    participation = team.term_participations.filter(project_version=team.project_version).order_by('-semester__school_year__label', '-id').first()
    captured = participation.requirements if participation else []
    if captured and (team.capstone_phase == StudentTeam.PHASE_EXTENDED or participation.closed_at):
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


@read_memoize
def cohort_context(team):
    journey = CapstoneJourney.objects.filter(team=team).select_related('intake_semester__school_year').first()
    if journey:
        if (journey.normal_completion_year != year_after(journey.intake_semester.school_year.label)
                or journey.extension_end_year != year_after(journey.normal_completion_year)):
            return None
        return {'intake': journey.intake_semester, 'normal_year': journey.normal_completion_year,
                'end_year': journey.extension_end_year, 'policy': journey.extension_policy,
                'completed_version': journey.completed_project_version}
    if team.capstone_phase == StudentTeam.PHASE_EXTENDED:
        return None
    # Current third-year intake is reliable. A fourth-year label alone is not.
    intake = team.semester if team.level == StudentTeam.LEVEL_3_CAPSTONE and team.semester.label == Semester.SECOND else None
    if not intake:
        from grading.grades.models import TeamGrade
        terms = Semester.objects.filter(label=Semester.SECOND).filter(
            Q(id__in=TeamGrade.all_objects.filter(team=team, scope='capstone').values('semester_id')) |
            Q(id__in=TeamStageProgress.all_objects.filter(team=team).values('semester_id')) |
            Q(id__in=team.term_participations.filter(is_extended=False).values('semester_id'))
        ).select_related('school_year').order_by('school_year__label')
        intake = terms.first()
    if not intake:
        return None
    normal_year = year_after(intake.school_year.label)
    return {'intake': intake, 'normal_year': normal_year, 'end_year': year_after(normal_year),
            'policy': EXTENSION_POLICY, 'completed_version': None}


def ensure_journey(team):
    context = cohort_context(team)
    if not context:
        return None
    journey, _ = CapstoneJourney.objects.get_or_create(team=team, defaults={
        'intake_semester': context['intake'], 'normal_completion_year': context['normal_year'],
        'extension_end_year': context['end_year'], 'extension_policy': context['policy']})
    return journey


def extension_eligibility(team, target):
    context = cohort_context(team)
    if not context or context['policy'] != EXTENSION_POLICY:
        return False, 'Original cohort requires review before an extension can be granted.', ''
    deadline = f'1st Semester, AY {context["end_year"]}'
    if context['completed_version'] == team.project_version:
        return False, 'This project is already completed.', deadline
    if target.label not in (Semester.FIRST, Semester.SECOND):
        return False, 'Automatic continuation is limited to regular semesters.', deadline
    if term_key(target) <= (context['normal_year'], 1):
        return False, 'The normal Capstone year has not ended.', deadline
    if term_key(target) > (context['end_year'], 1):
        return False, 'Extension deadline reached. Institutional review is required.', deadline
    return True, '', deadline


def enrollment_check(team, target):
    from user_management.academic_records.models import StudentAcademicRecord
    if target.pk is None:
        return False, 'Every continuing member, including the leader, must be enrolled in fourth year for the target term.'
    roster = set(team.memberships.values_list('student_id', flat=True)) | {team.leader_id}
    enrolled = set(StudentAcademicRecord.objects.filter(semester=target, student_id__in=roster,
        year_level=StudentAcademicRecord.FOURTH_YEAR, student__is_active=True).values_list('student_id', flat=True))
    if roster != enrolled:
        return False, 'Every continuing member, including the leader, must be enrolled in fourth year for the target term.'
    sections = set(StudentAcademicRecord.objects.filter(semester=target, student_id__in=roster)
                   .exclude(section='').values_list('section', flat=True))
    if len(sections) > 1:
        return False, 'Continuing members must share the same target-term section. Review the official roster.'
    conflict = StudentTeam.objects.filter(semester=target, level__in=(StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE)).exclude(pk=team.pk).filter(
        Q(leader_id__in=roster) | Q(memberships__student_id__in=roster)).exists()
    if conflict:
        return False, 'A member already belongs to another Capstone team in the target semester.'
    return True, ''


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
        if grade and grade.status == TeamGrade.STATUS_PUBLISHED and grade.verdict == TeamGrade.VERDICT_FAILED:
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
    row.is_extended = team.capstone_phase == StudentTeam.PHASE_EXTENDED
    row.requirements = requirements if requirements is not None else requirements_for(team)
    row.snapshot = team_snapshot(team)
    row.save()
    ensure_journey(team)
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


def build_capstone_review(source, target, *, late=False):
    from grading.grades.models import TeamGrade
    from user_management.academic_records.models import StudentAcademicRecord
    kind = transition_kind(source, target)
    teams = StudentTeam.objects.filter(semester=source, level__in=(StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE)) if source else StudentTeam.objects.none()
    if late and source:
        teams = StudentTeam.objects.filter(term_participations__semester=source,
            term_participations__outcome='failed', term_participations__closed_at__isnull=False).exclude(term_participations__semester=target)
    rows, fingerprints = [], []
    for team in teams.select_related('semester__school_year', 'leader', 'adviser').order_by('name', 'pk'):
        requirements = requirements_for(team)
        outcome, grade, explanation = project_outcome(team, requirements)
        enrolled, enrollment_reason = enrollment_check(team, target)
        eligible, allowance_reason, deadline = extension_eligibility(team, target)
        extended = team.capstone_phase == StudentTeam.PHASE_EXTENDED
        destination, can_include, needs_choice = 'needs_review', False, False
        if kind == 'continue' and not extended:
            context = cohort_context(team)
            if team.level == StudentTeam.LEVEL_3_CAPSTONE and context and context['normal_year'] == target.school_year.label:
                # A normal Capstone 1 cohort does not finish after its first term.
                destination, can_include = 'continue', enrolled
            else:
                explanation = 'The original cohort and current phase require review. Year level alone cannot grant continuation.'
        elif kind in ('continue', 'close_cycle'):
            context = cohort_context(team)
            if not extended and (not context or context['normal_year'] != source.school_year.label):
                destination = 'needs_review'
                explanation = 'Original cohort and expected normal completion term require review.'
            elif outcome == 'completed':
                destination = 'history'
            elif extended and eligible and enrolled:
                destination, can_include = 'extended', True
                authority = TeamRecoveryAuthorization.objects.filter(team=team, semester=source,
                    consumed_at__isnull=True, source_grade=grade, project_version=team.project_version).exists() if grade else False
                needs_choice = outcome == 'failed' and not authority
            elif outcome == 'failed':
                destination = 'extended' if eligible else 'institutional_review'
                can_include, needs_choice = eligible and enrolled, eligible and enrolled
        reason = (allowance_reason if (extended or outcome == 'failed') and not eligible else '') or (enrollment_reason if destination in ('continue', 'extended') and not enrolled else '') or explanation
        context = cohort_context(team)
        row = {'team_id': team.pk, 'name': team.name, 'project_title': team.project_title,
               'project_version': team.project_version, 'outcome': outcome, 'destination': destination,
               'is_extended': extended, 'can_include': can_include, 'requires_project_choice': needs_choice,
               'enrolled': enrolled, 'reason': reason, 'extension_deadline': deadline,
               'original_cohort': context['intake'].display_name if context else None,
               'source_grade_id': grade.pk if grade else None}
        rows.append(row)
        roster = set(team.memberships.values_list('student_id', flat=True)) | {team.leader_id}
        fingerprints.append({'team': team_snapshot(team), 'requirements': requirements, 'row': row,
            'grades': list(TeamGrade.all_objects.filter(team=team, project_version=team.project_version).order_by('pk')
                .values('id', 'semester_id', 'defense_stage_id', 'status', 'verdict', 'updated_at', 'revisions_cleared_at', 'final_grade')),
            'enrollment': list(StudentAcademicRecord.objects.filter(semester_id=target.pk, student_id__in=roster).order_by('pk').values('id', 'student_id', 'year_level', 'section')),
            'recoveries': list(team.recovery_authorizations.order_by('pk').values('id', 'action', 'project_version', 'consumed_at'))})
        from repository.deliverables.models import DeliverableSubmission
        fingerprints[-1]['files'] = list(DeliverableSubmission.all_objects.filter(team=team,
            project_version=team.project_version).order_by('pk').values('id', 'status', 'uploaded_at', 'reviewed_at', 'file', 'file_name', 'file_size'))
    counts = {key: sum(r['destination'] == key for r in rows) for key in ('history', 'continue', 'extended', 'needs_review', 'institutional_review')}
    revision = sha256(json.dumps({'source': source.pk if source else None,
        'target': [target.school_year_id, target.label, target.starts_on, target.ends_on],
        'kind': kind, 'teams': fingerprints}, sort_keys=True, default=str).encode()).hexdigest()
    return {'kind': kind, 'teams': rows, 'counts': counts, 'total': len(rows), 'revision': revision,
            'requires_review': bool(rows), 'late': late}


def validate_decisions(review, decisions, reason):
    if not isinstance(decisions, list):
        raise ValidationError({'decisions': 'Provide the returning-team decisions as a list.'})
    indexed, rows = {}, {row['team_id']: row for row in review['teams']}
    for decision in decisions:
        if not isinstance(decision, dict) or type(decision.get('team_id')) is not int or decision['team_id'] not in rows:
            raise ValidationError({'decisions': 'A selected team is not part of this transition preview.'})
        team_id = decision['team_id']
        if team_id in indexed or type(decision.get('include')) is not bool:
            raise ValidationError({'decisions': 'Each team needs one decision with a boolean inclusion value.'})
        row = rows[team_id]
        if decision['include']:
            if not row['can_include']:
                raise ValidationError({'decisions': f'{row["name"]}: {row["reason"]}'})
            if row['requires_project_choice']:
                if decision.get('project_choice') not in ('continue', 'new'):
                    raise ValidationError({'decisions': f'Choose a project option for {row["name"]}.'})
                if not (str(decision.get('reason') or reason).strip()):
                    raise ValidationError({'reason': 'Record the institutional recovery decision or reference.'})
                title = decision.get('project_title', '')
                if decision['project_choice'] == 'new' and (not isinstance(title, str) or not title.strip() or len(title.strip()) > 255):
                    raise ValidationError({'project_title': 'Enter a replacement project title up to 255 characters.'})
        indexed[team_id] = decision
    # Each eligible failed team needs an explicit include/exclude decision.
    if any(r['requires_project_choice'] and r['team_id'] not in indexed for r in rows.values()):
        raise ValidationError({'decisions': 'Review every eligible failed team before confirming.'})
    return indexed


@transaction.atomic
def authorize_recovery(team, source_grade, *, target, choice, title='', reason='', actor=None):
    """One recovery implementation for Grade Center and semester continuation."""
    from defense.stages.models import DefenseStage
    if not actor or not (getattr(actor, 'role', None) == 'admin' or actor.is_superuser):
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied('Only an administrator can authorize Capstone recovery.')
    current = StudentTeam.objects.select_for_update().only('semester_id', 'project_version').get(pk=team.pk)
    if (current.semester_id, current.project_version) != (team.semester_id, team.project_version):
        raise ValidationError('The team changed. Refresh the recovery decision.')
    latest = latest_stage_assessment(team, source_grade.defense_stage_id)
    if not latest or latest.pk != source_grade.pk:
        raise ValidationError('This failure has been superseded by a later assessment. Review the current attempt.')
    source_grade = latest
    if source_grade.team_id != team.pk or source_grade.project_version != team.project_version or source_grade.verdict not in ('failed', 'project_rejected'):
        raise ValidationError('Recovery requires the current project\'s Failed or Project Rejected assessment.')
    if not reason.strip():
        raise ValidationError('Record the institutional decision or authorization reference.')
    if team.semester_id != target.pk:
        raise ValidationError('The recovery destination must be the team\'s operational semester.')
    from .term_scope import term_status_for_team
    if term_status_for_team(team) != 'active':
        raise ValidationError('Recovery requires an open participation in the active operational semester.')
    if team.capstone_phase == StudentTeam.PHASE_EXTENDED:
        allowed, why, _ = extension_eligibility(team, target)
        if not allowed:
            raise ValidationError(why)
    if TeamRecoveryAuthorization.objects.filter(team=team, semester=target, project_version=team.project_version,
            consumed_at__isnull=True).exists():
        raise ValidationError('Another recovery decision is already authorized for this project in this term.')
    if choice == 'continue':
        if source_grade.verdict != 'failed':
            raise ValidationError('A rejected concept needs an authorized replacement concept.')
        stage = source_grade.defense_stage
    elif choice == 'new':
        if not title.strip() or len(title.strip()) > 255:
            raise ValidationError('Enter a replacement concept title (up to 255 characters).')
        stage = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'id').first()
    else:
        raise ValidationError('Select a valid recovery decision.')
    if not stage:
        raise ValidationError('Configure the applicable defense stage before authorizing recovery.')
    authorization = TeamRecoveryAuthorization.objects.create(team=team, semester=target, source_grade=source_grade,
        defense_stage=stage, project_version=team.project_version, previous_project_title=team.project_title,
        action='retake' if choice == 'continue' else 'new_concept', reason=reason.strip(), authorized_by=actor,
        replacement_project_version=team.project_version + 1 if choice == 'new' else None,
        replacement_project_title=title.strip() if choice == 'new' else '')
    if choice == 'new':
        team.project_version += 1
        team.project_title = title.strip()
        team.project_pending = False
        team.status = StudentTeam.STATUS_PENDING
        team.unlocked_stages = []
    team.current_defense_stage = stage.label
    team.ready_for_stage = None
    team.save()
    TeamStageProgress.objects.get_or_create(team=team, semester=target, defense_stage=stage,
        project_version=team.project_version, defaults={'status': TeamStageProgress.STATUS_LOCKED, 'created_by': actor})
    if choice == 'new':
        from grading.grades.services import GradeContextService
        GradeContextService.get_or_create_unscheduled_team(team, stage_label=stage.label)
    else:
        from repository.deliverables.redefense import snapshot_hearing, refresh_files
        original = evidence_team(team, source_grade)
        snapshot_hearing(source_grade.schedule, original, stage)
        refresh_files(team, stage)
    return authorization


def carry_recovery_authority(team, source, target):
    """Carry unused permission inside the same allowance, never another project reset."""
    authority = TeamRecoveryAuthorization.objects.filter(team=team, semester=source,
        consumed_at__isnull=True).filter(Q(action='retake', project_version=team.project_version) |
            Q(action='new_concept', replacement_project_version=team.project_version)).order_by('-pk').first()
    if not authority:
        return
    TeamRecoveryAuthorization.objects.create(team=team, semester=target, source_grade=authority.source_grade,
        defense_stage=authority.defense_stage, project_version=authority.project_version,
        previous_project_title=authority.previous_project_title, action=authority.action,
        reason=authority.reason, authorized_by=authority.authorized_by,
        replacement_project_version=authority.replacement_project_version,
        replacement_project_title=authority.replacement_project_title)
    authority.consumed_at = timezone.now()
    authority.save(update_fields=['consumed_at'])
    TeamStageProgress.objects.get_or_create(team=team, semester=target, defense_stage=authority.defense_stage,
        project_version=team.project_version, defaults={'status': TeamStageProgress.STATUS_LOCKED})


def apply_capstone_transition(source, target, review, decisions, *, actor, log, reason='', late=False):
    indexed = validate_decisions(review, decisions, reason)
    if review['kind'] not in ('continue', 'close_cycle'):
        return []
    applied = []
    for item in review['teams']:
        team = StudentTeam.objects.select_for_update(of=('self',)).select_related('semester__school_year', 'leader', 'adviser').get(pk=item['team_id'])
        requirements = requirements_for(team)
        old = team.term_participations.filter(semester=source).first()
        if not late:
            old = capture_participation(team, requirements=requirements)
            old.outcome = item['outcome'] if not (review['kind'] == 'continue' and not item['is_extended']) else 'open'
            old.closed_at, old.transition = timezone.now(), log
            old.save()
        decision = indexed.get(team.pk, {})
        include = decision.get('include', item['can_include'] and not item['requires_project_choice'])
        if include:
            enrolled, why = enrollment_check(team, target)
            if not enrolled:
                raise ValidationError(why)
            if team.term_participations.filter(semester=target).exists():
                raise ValidationError('This team already has target-term participation. Refresh the preview.')
            journey = ensure_journey(team)
            team.semester = target
            team.level, team.year_level = StudentTeam.LEVEL_4_CAPSTONE, '4th Year'
            from user_management.academic_records.models import StudentAcademicRecord
            section = StudentAcademicRecord.objects.filter(student=team.leader, semester=target).values_list('section', flat=True).first()
            if section:
                team.section = section
            if item['destination'] == 'extended':
                team.capstone_phase = StudentTeam.PHASE_EXTENDED
                team.status = StudentTeam.STATUS_DELAYED
            else:
                team.capstone_phase = StudentTeam.PHASE_ACTIVE
                next_stage = next((r for r in requirements if not stage_cleared(team, r)), None)
                from defense.stages.models import DefenseStage
                team.current_defense_stage = (DefenseStage.objects.filter(pk=next_stage['id']).values_list('label', flat=True).first()
                    or next_stage['label']) if next_stage else None
            team.ready_for_stage = None
            team.save()
            if item['requires_project_choice']:
                from grading.grades.models import TeamGrade
                grade = TeamGrade.all_objects.select_related('defense_stage').get(pk=item['source_grade_id'])
                authorize_recovery(team, grade, target=target, choice=decision['project_choice'],
                    title=decision.get('project_title', ''), reason=str(decision.get('reason') or reason), actor=actor)
            else:
                carry_recovery_authority(team, source, target)
            new = capture_participation(team, requirements=configured_requirements() if decision.get('project_choice') == 'new' else requirements)
            new.transition = log
            new.save(update_fields=['transition', 'updated_at'])
            applied.append(team.pk)
        elif item['destination'] == 'history' and old and old.outcome == 'completed':
            journey = ensure_journey(team)
            if journey:
                journey.completed_project_version = team.project_version
                journey.save(update_fields=['completed_project_version'])
    return applied


def continue_enrolled_normal_team(team, target):
    """Enrollment rollover may carry a normal cohort; never grants an extension."""
    if not target.is_active or transition_kind(team.semester, target) != 'continue' or team.capstone_phase == StudentTeam.PHASE_EXTENDED or team.level != StudentTeam.LEVEL_3_CAPSTONE:
        return False
    enrolled, _ = enrollment_check(team, target)
    if not enrolled:
        return False
    requirements = requirements_for(team)
    old = team.term_participations.filter(semester=team.semester).first()
    if old and old.closed_at and old.outcome != 'open':
        return False
    if not old or not old.closed_at:
        old = capture_participation(team, requirements=requirements)
        old.closed_at = timezone.now()
        old.save(update_fields=['closed_at', 'updated_at'])
    source = team.semester
    team.semester, team.level, team.year_level = target, StudentTeam.LEVEL_4_CAPSTONE, '4th Year'
    team.capstone_phase = StudentTeam.PHASE_ACTIVE
    team.ready_for_stage = None
    next_stage = next((r for r in requirements if not stage_cleared(team, r)), None)
    from defense.stages.models import DefenseStage
    team.current_defense_stage = (DefenseStage.objects.filter(pk=next_stage['id']).values_list('label', flat=True).first()
        or next_stage['label']) if next_stage else None
    from user_management.academic_records.models import StudentAcademicRecord
    section = StudentAcademicRecord.objects.filter(student=team.leader, semester=target).values_list('section', flat=True).first()
    if section:
        team.section = section
    team.save()
    carry_recovery_authority(team, source, target)
    capture_participation(team, requirements=requirements)
    return True


def returning_source(target):
    if target.label != Semester.SECOND:
        return None
    return Semester.objects.filter(school_year=target.school_year, label=Semester.FIRST).first()


@transaction.atomic
def confirm_returning_teams(target, *, actor, decisions, preview_revision, reason='', request_id=None):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    from academic_period_management.models import SemesterTransitionLog
    list(Semester.objects.select_for_update().order_by('pk'))
    target.refresh_from_db()
    if not target.is_active or not (getattr(actor, 'role', None) == 'admin' or actor.is_superuser):
        raise ValidationError('Returning-team review requires an administrator and the active target semester.')
    if request_id:
        previous = SemesterTransitionLog.objects.filter(request_id=request_id).first()
        if previous:
            if previous.operation != 'returning' or previous.to_semester_id != target.pk or previous.changed_by_id != actor.pk:
                raise ValidationError('This request identity has already been used for another operation.')
            if previous.reason != reason or previous.impact_snapshot.get('decisions', []) != decisions:
                raise ValidationError('This request has already completed with different returning-team decisions.')
            return previous.impact_snapshot.get('applied_team_ids', [])
    source = returning_source(target)
    source_teams = StudentTeam.objects.filter(term_participations__semester=source)
    from django.contrib.auth import get_user_model
    from grading.grades.models import TeamGrade
    from user_management.academic_records.models import StudentAcademicRecord
    ids = set(source_teams.values_list('leader_id', flat=True)) | set(
        TeamMembership.objects.filter(team__in=source_teams).values_list('student_id', flat=True))
    list(get_user_model().objects.select_for_update().filter(pk__in=ids).order_by('pk'))
    list(StudentAcademicRecord.objects.select_for_update().filter(student_id__in=ids, semester=target).order_by('pk'))
    list(source_teams.select_for_update().order_by('pk'))
    list(TeamGrade.all_objects.select_for_update().filter(team__in=source_teams).order_by('pk'))
    review = build_capstone_review(source, target, late=True)
    if preview_revision != review['revision']:
        raise ValidationError({'code': 'stale_preview', 'detail': 'Returning-team eligibility changed. Refresh the review.', 'capstone_review': review})
    log = SemesterTransitionLog.objects.create(operation='returning', from_semester=source, to_semester=target,
        changed_by=actor, request_id=request_id, preview_revision=preview_revision, reason=reason,
        impact_snapshot={'capstone_review': review, 'decisions': decisions})
    applied = apply_capstone_transition(source, target, review, decisions, actor=actor, log=log, reason=reason, late=True)
    log.impact_snapshot['applied_team_ids'] = applied
    log.save(update_fields=['impact_snapshot'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD, action='semester.returning_teams',
        target=target, actor=actor, new_values={'team_ids': applied, 'decisions': decisions}, reason=reason, strict=True)
    return applied


def prior_capstone_team(student_ids, target, *, exclude_team=None):
    """Fresh imports cannot bypass continuation or reset a returning student's allowance."""
    return StudentTeam.objects.filter(level__in=(StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE)).exclude(
        semester=target).exclude(pk=exclude_team).filter(
        Q(leader_id__in=student_ids) | Q(memberships__student_id__in=student_ids)).distinct().first()


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
