from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam, TeamMembership

from .models import PeerEvaluationSubmission, StudentPeerGrade, TeamGrade
from .services import (
    GradeContextService,
    display_name,
    find_matching_rubric,
    peer_grading_allowed_for_grade,
    require_grade_editable,
    require_matching_rubric,
)


def _resolve_evaluatee(team, evaluatee_id):
    try:
        target_id = int(evaluatee_id)
    except (TypeError, ValueError) as exc:
        raise ValidationError({'evaluateeId': 'Evaluatee is required.'}) from exc

    for membership in team.memberships.select_related('student').all():
        if membership.student_id == target_id:
            return membership.student

    raise ValidationError({'evaluateeId': 'Evaluatee must be a member of this team.'})


def _grade_for_team(team):
    return GradeContextService.get_for_current_student_peer_context(team)


def _peer_max_score(grade):
    rubric = require_matching_rubric(grade, Rubric.EVAL_PEER)
    total = sum(
        Decimal(str(criterion.max_score))
        for criterion in rubric.criteria.all()
    )
    if total <= 0:
        raise ValidationError({'rubric': 'The configured peer rubric must have a positive max score.'})
    return total


def required_peer_submission_count(team):
    """Each member evaluates every other member: N * (N - 1) submissions."""
    member_count = team.memberships.count()
    if member_count <= 1:
        return 0
    return member_count * (member_count - 1)


def peer_submission_count(grade):
    return PeerEvaluationSubmission.objects.filter(team_grade=grade).count()


def is_team_peer_eval_complete(grade):
    required = required_peer_submission_count(grade.team)
    if required == 0:
        return True
    return peer_submission_count(grade) >= required


def is_evaluator_peer_complete(grade, evaluator):
    member_count = grade.team.memberships.count()
    if member_count <= 1:
        return True
    required = member_count - 1
    submitted = PeerEvaluationSubmission.objects.filter(
        team_grade=grade,
        evaluator=evaluator,
    ).count()
    return submitted >= required


def peer_completion_summary(grade):
    memberships = list(grade.team.memberships.select_related('student').all())
    required = required_peer_submission_count(grade.team)
    submitted = peer_submission_count(grade)
    evaluators_total = len(memberships)
    evaluators_done = 0
    missing_evaluators = []

    for membership in memberships:
        student = membership.student
        if is_evaluator_peer_complete(grade, student):
            evaluators_done += 1
        else:
            need = max(evaluators_total - 1, 0)
            have = PeerEvaluationSubmission.objects.filter(
                team_grade=grade,
                evaluator=student,
            ).count()
            missing_evaluators.append(
                {
                    'student_id': student.id,
                    'student_name': display_name(student),
                    'submitted': have,
                    'required': need,
                }
            )

    return {
        'submitted': submitted,
        'required': required,
        'evaluators_done': evaluators_done,
        'evaluators_total': evaluators_total,
        'complete': is_team_peer_eval_complete(grade),
        'missing_evaluators': missing_evaluators,
    }


def _build_peer_rows_for_complete_grade(grade, memberships, max_scale):
    peer_rows = []
    normalized_total = Decimal('0.00')

    for membership in memberships:
        evaluatee = membership.student
        submissions = PeerEvaluationSubmission.objects.filter(
            team_grade=grade,
            evaluatee=evaluatee,
        )
        averages = []
        for submission in submissions:
            if submission.max_score <= 0:
                continue
            ratio = submission.total_score / submission.max_score
            averages.append(ratio * max_scale)

        if not averages:
            return None

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

    if not peer_rows:
        return None

    return peer_rows, normalized_total


@transaction.atomic
def sync_peer_summaries(grade):
    memberships = list(grade.team.memberships.select_related('student').all())
    StudentPeerGrade.objects.filter(team_grade=grade).delete()

    if not memberships:
        grade.peer_score = None
        grade.save()
        return

    if not is_team_peer_eval_complete(grade):
        grade.peer_score = None
        grade.save()
        from .services import maybe_auto_finalize_passed_grade

        maybe_auto_finalize_passed_grade(grade)
        return

    max_scale = _peer_max_score(grade)
    built = _build_peer_rows_for_complete_grade(grade, memberships, max_scale)
    if built is None:
        grade.peer_score = None
        grade.save()
        return

    peer_rows, normalized_total = built
    StudentPeerGrade.objects.bulk_create(peer_rows)
    grade.peer_score = (normalized_total / Decimal(len(peer_rows))).quantize(Decimal('0.01'))
    grade.save()
    from .services import maybe_auto_finalize_passed_grade

    maybe_auto_finalize_passed_grade(grade)


@transaction.atomic
def submit_student_peer_evaluation(*, evaluator, team_id, evaluatee_id, breakdown, total, max_score):
    if getattr(evaluator, 'role', None) != 'student':
        raise ValidationError({'detail': 'Only students can submit peer evaluations.'})

    try:
        team = StudentTeam.objects.prefetch_related('memberships__student').get(pk=team_id)
    except (StudentTeam.DoesNotExist, ValueError, TypeError) as exc:
        raise ValidationError({'teamId': 'Team not found.'}) from exc

    if not TeamMembership.objects.filter(team=team, student=evaluator).exists():
        raise ValidationError({'teamId': 'You are not a member of this team.'})

    evaluatee = _resolve_evaluatee(team, evaluatee_id)
    if evaluatee.id == evaluator.id:
        raise ValidationError({'evaluateeId': 'You cannot evaluate yourself.'})

    grade = _grade_for_team(team)

    if grade.status in TeamGrade.LOCKED_STATUSES:
        raise ValidationError({'detail': 'Grades for this team have already been finalized and cannot be changed.'})
    require_grade_editable(grade)

    if not peer_grading_allowed_for_grade(grade):
        raise ValidationError({'detail': 'Peer grading is not open for this event or stage.'})
    require_matching_rubric(grade, Rubric.EVAL_PEER)

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
