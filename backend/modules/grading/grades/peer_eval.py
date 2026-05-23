from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam, TeamMembership

from .models import PeerEvaluationSubmission, StudentPeerGrade, TeamGrade
from .services import (
    _scope_for_team,
    _sync_unscheduled_team,
    canonical_capstone_grade_for_team,
    display_name,
    find_matching_rubric,
    peer_grading_allowed_for_grade,
    resolve_canonical_capstone_grade,
)


def _resolve_evaluatee(team, evaluatee_name):
    target = (evaluatee_name or '').strip().lower()
    if not target:
        raise ValidationError({'evaluateeName': 'Evaluatee name is required.'})

    for membership in team.memberships.select_related('student').all():
        student = membership.student
        candidates = {
            display_name(student).lower(),
            student.username.lower(),
            f'{student.first_name} {student.last_name}'.strip().lower(),
        }
        if target in candidates:
            return student

    raise ValidationError({'evaluateeName': f'No teammate matched "{evaluatee_name}".'})


def _grade_for_team(team):
    scope = _scope_for_team(team)
    if scope == TeamGrade.SCOPE_CAPSTONE:
        grade = canonical_capstone_grade_for_team(team, team.semester)
        if grade is None:
            grade, _ = _sync_unscheduled_team(team)
            grade = resolve_canonical_capstone_grade(grade)
        else:
            grade = resolve_canonical_capstone_grade(grade)
        return grade

    grade = (
        TeamGrade.objects.filter(team=team, scope=scope)
        .order_by('-updated_at', '-id')
        .first()
    )
    if grade:
        return grade
    grade, _ = _sync_unscheduled_team(team)
    return grade


def _peer_max_score(grade):
    rubric = find_matching_rubric(grade, Rubric.EVAL_PEER)
    if rubric:
        total = sum(
            Decimal(str(criterion.max_score))
            for criterion in rubric.criteria.all()
        )
        if total > 0:
            return total
    return Decimal('5.00')


@transaction.atomic
def sync_peer_summaries(grade):
    memberships = list(grade.team.memberships.select_related('student').all())
    if not memberships:
        grade.peer_score = None
        grade.save()
        return

    max_scale = _peer_max_score(grade)
    StudentPeerGrade.objects.filter(team_grade=grade).delete()
    normalized_total = Decimal('0.00')
    peer_rows = []

    for membership in memberships:
        evaluatee = membership.student
        submissions = PeerEvaluationSubmission.objects.filter(
            team_grade=grade,
            evaluatee=evaluatee,
        )
        if not submissions.exists():
            continue

        averages = []
        for submission in submissions:
            if submission.max_score <= 0:
                continue
            ratio = submission.total_score / submission.max_score
            averages.append(ratio * max_scale)

        if not averages:
            continue

        average = (sum(averages) / Decimal(len(averages))).quantize(Decimal('0.01'))
        peer_rows.append(
            StudentPeerGrade(
                team_grade=grade,
                student=evaluatee,
                average_score=average,
                max_score=max_scale,
            )
        )
        normalized_total += average / max_scale * Decimal('100')

    if peer_rows:
        StudentPeerGrade.objects.bulk_create(peer_rows)
        grade.peer_score = (normalized_total / Decimal(len(peer_rows))).quantize(Decimal('0.01'))
    else:
        grade.peer_score = None

    grade.save()
    from .services import maybe_auto_finalize_passed_grade

    maybe_auto_finalize_passed_grade(grade)


@transaction.atomic
def submit_student_peer_evaluation(*, evaluator, team_id, evaluatee_name, breakdown, total, max_score):
    if getattr(evaluator, 'role', None) != 'student':
        raise ValidationError({'detail': 'Only students can submit peer evaluations.'})

    try:
        team = StudentTeam.objects.prefetch_related('memberships__student').get(pk=team_id)
    except (StudentTeam.DoesNotExist, ValueError, TypeError) as exc:
        raise ValidationError({'teamId': 'Team not found.'}) from exc

    if not TeamMembership.objects.filter(team=team, student=evaluator).exists():
        raise ValidationError({'teamId': 'You are not a member of this team.'})

    evaluatee = _resolve_evaluatee(team, evaluatee_name)
    if evaluatee.id == evaluator.id:
        raise ValidationError({'evaluateeName': 'You cannot evaluate yourself.'})

    grade = _grade_for_team(team)
    if not peer_grading_allowed_for_grade(grade):
        raise ValidationError({'detail': 'Peer grading is not open for this event or stage.'})

    total_decimal = Decimal(str(total)).quantize(Decimal('0.01'))
    max_decimal = Decimal(str(max_score)).quantize(Decimal('0.01'))
    if max_decimal <= 0:
        raise ValidationError({'max': 'Max score must be greater than 0.'})
    if total_decimal < 0 or total_decimal > max_decimal:
        raise ValidationError({'total': 'Total score must be between 0 and max.'})

    PeerEvaluationSubmission.objects.update_or_create(
        team_grade=grade,
        evaluator=evaluator,
        evaluatee=evaluatee,
        defaults={
            'total_score': total_decimal,
            'max_score': max_decimal,
            'breakdown': breakdown or [],
        },
    )
    sync_peer_summaries(grade)

    return {
        'teamId': team.id,
        'evaluateeId': evaluatee.id,
        'evaluateeName': display_name(evaluatee),
        'peerScore': grade.peer_score,
    }


def peer_criteria_payload(team):
    if not team:
        return []

    grade = _grade_for_team(team)
    if not peer_grading_allowed_for_grade(grade):
        return []

    rubric = find_matching_rubric(grade, Rubric.EVAL_PEER)
    if rubric:
        return [
            {
                'name': criterion.name,
                'maxScore': float(criterion.max_score),
                'description': criterion.description or '',
            }
            for criterion in rubric.criteria.order_by('display_order', 'id')
        ]

    if team.is_capstone:
        return [
            {'name': 'Teamwork', 'maxScore': 5.0, 'description': ''},
            {'name': 'Contribution', 'maxScore': 5.0, 'description': ''},
        ]
    return []


def peer_submissions_for_evaluator(team, evaluator):
    if not team:
        return []

    grade = _grade_for_team(team)
    rows = PeerEvaluationSubmission.objects.filter(
        team_grade=grade,
        evaluator=evaluator,
    ).select_related('evaluatee')
    return [
        {
            'evaluateeId': row.evaluatee_id,
            'evaluateeName': display_name(row.evaluatee),
            'total': float(row.total_score),
            'max': float(row.max_score),
            'breakdown': row.breakdown or [],
        }
        for row in rows
    ]
