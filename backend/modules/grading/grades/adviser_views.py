from decimal import Decimal

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView as APIView

from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam
from defense.scheduler.models import DefenseSchedule
from .models import GradeBreakdown, StudentStageGrade, TeamGrade
from .peer_eval import recalculate_student_grade
from .availability import adviser_grading_unavailable_reason
from .serializers import TeamGradeSerializer
from .services import (
    GradeContextService,
    active_semester,
    adviser_capstone_grades_for_user,
    assigned_adviser_rubric_payload,
    grade_queryset,
    require_grade_editable,
    require_matching_rubric,
    resolve_canonical_capstone_grade,
)


class _AdviserGradeSubmitSerializer(drf_serializers.Serializer):
    adviser_score = drf_serializers.DecimalField(
        max_digits=5, decimal_places=2, min_value=0, max_value=100, required=False, allow_null=True
    )
    rubric_id = drf_serializers.IntegerField(required=False, allow_null=True)
    criteria_scores = drf_serializers.ListField(
        child=drf_serializers.DictField(),
        required=False,
        default=list,
    )
    team_criteria_scores = drf_serializers.ListField(
        child=drf_serializers.DictField(),
        required=False,
        default=list,
    )
    student_submissions = drf_serializers.ListField(
        child=drf_serializers.DictField(),
        required=False,
        default=list,
    )

    def save(self):
        grade = self.context['grade']

        try:
            assigned = require_matching_rubric(grade, Rubric.EVAL_ADVISER)
        except DjangoValidationError as exc:
            raise drf_serializers.ValidationError(
                exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}
            ) from exc

        rubric_id = self.validated_data.get('rubric_id') or assigned.pk
        if rubric_id and assigned and rubric_id != assigned.pk:
            raise drf_serializers.ValidationError(
                {'rubric_id': 'Use the adviser rubric assigned for this defense stage.'}
            )

        try:
            rubric = Rubric.objects.prefetch_related('criteria').get(
                pk=rubric_id, evaluation_type=Rubric.EVAL_ADVISER
            )
        except Rubric.DoesNotExist as exc:
            raise drf_serializers.ValidationError(
                {'rubric_id': 'Adviser rubric does not exist.'}
            ) from exc

        target_type = rubric.target_type
        criteria_scores = self.validated_data.get('criteria_scores') or []
        team_criteria_scores = self.validated_data.get('team_criteria_scores') or []
        student_submissions = self.validated_data.get('student_submissions') or []

        if not team_criteria_scores and criteria_scores:
            team_criteria_scores = criteria_scores

        memberships = list(grade.team.memberships.select_related('student').all())
        student_map = {m.student_id: m.student for m in memberships}

        from .scoring import rubric_score_rows, rubric_rows_percentage

        breakdowns = []
        student_adviser_scores = {}

        def record(rows, student=None):
            breakdowns.extend(
                GradeBreakdown(
                    team_grade=grade, student=student, rubric=rubric,
                    evaluation_type=GradeBreakdown.EVAL_ADVISER,
                    criterion_name=row['criterion'].name, score=row['score'],
                    max_score=row['max_score'], weight_snapshot=row['weight'],
                    display_order=row['criterion'].display_order,
                ) for row in rows
            )

        try:
            team_rows = []
            if target_type in (Rubric.TARGET_TEAM, Rubric.TARGET_BOTH):
                team_rows = rubric_score_rows(
                    rubric, team_criteria_scores,
                    target_type=Rubric.TARGET_TEAM if target_type == Rubric.TARGET_BOTH else None,
                )
                record(team_rows)

            if target_type == Rubric.TARGET_TEAM:
                team_score = rubric_rows_percentage(team_rows)
                student_adviser_scores = {membership.student_id: team_score for membership in memberships}
            else:
                submitted_students = set()
                for sub in student_submissions:
                    s_id = drf_serializers.IntegerField(min_value=1).run_validation(sub.get('student_id'))
                    if s_id not in student_map or s_id in submitted_students:
                        raise DjangoValidationError({'student_submissions': 'Submit each current team member exactly once.'})
                    submitted_students.add(s_id)
                    rows = rubric_score_rows(
                        rubric, sub.get('criteria_scores'),
                        target_type=Rubric.TARGET_INDIVIDUAL if target_type == Rubric.TARGET_BOTH else None,
                    )
                    record(rows, student_map[s_id])
                    student_adviser_scores[s_id] = rubric_rows_percentage(team_rows + rows)
                if submitted_students != set(student_map):
                    raise DjangoValidationError({'student_submissions': 'Score every current team member.'})
        except DjangoValidationError as exc:
            raise drf_serializers.ValidationError(
                exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}
            ) from exc

        GradeBreakdown.objects.filter(
            team_grade=grade, evaluation_type=GradeBreakdown.EVAL_ADVISER
        ).delete()
        if breakdowns:
            GradeBreakdown.objects.bulk_create(breakdowns)

        all_student_scores = []
        for m in memberships:
            sg, _ = StudentStageGrade.objects.get_or_create(team_grade=grade, student=m.student)
            s_score = student_adviser_scores.get(m.student_id)
            sg.adviser_score = s_score
            sg.save()
            recalculate_student_grade(sg)
            if s_score is not None:
                all_student_scores.append(s_score)

        if all_student_scores:
            grade.adviser_score = (sum(all_student_scores) / Decimal(len(all_student_scores))).quantize(Decimal('0.01'))

        grade.save()
        # The grade may have been read with these relations before bulk writes.
        # Return the new evaluation and per-student scores, not those old rows.
        cached = getattr(grade, '_prefetched_objects_cache', {})
        cached.pop('breakdowns', None)
        cached.pop('student_grades', None)
        return grade


class AdviserGradeListView(APIView):
    """
    GET /api/grade-center/adviser-grades/
    Returns TeamGrade records for capstone teams where the authenticated
    user is the adviser, along with a simple count summary.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        canonical_rows = adviser_capstone_grades_for_user(request.user)
        total = len(canonical_rows)
        graded = sum(1 for grade in canonical_rows if grade.adviser_score is not None)
        semester = active_semester()
        adviser_on = (
            getattr(semester, 'capstone_adviser_grading_enabled', True) if semester else True
        )
        grade_payload = []
        for grade in canonical_rows:
            row = TeamGradeSerializer(grade).data
            row.update(assigned_adviser_rubric_payload(grade))
            reason = adviser_grading_unavailable_reason(grade)
            row.update(adviser_grading_available=not reason, adviser_grading_unavailable_reason=reason)
            row['session_id'] = str(grade.schedule.session_id) if grade.schedule_id else None
            grade_payload.append(row)
        return Response({
            'grades': grade_payload,
            'counts': {
                'all': total,
                'graded': graded,
                'pending': total - graded,
            },
            'adviser_grading_enabled': adviser_on,
        })


class AdviserSubmitGradeView(APIView):
    """
    POST /api/grade-center/adviser-grades/<grade_id>/submit/
    Adviser submits their score (and optional per-criterion breakdown) for a
    team they advise.
    """

    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, grade_id):
        semester = active_semester()
        if semester and not getattr(semester, 'capstone_adviser_grading_enabled', True):
            return Response(
                {'detail': 'Adviser grading is disabled for the active term.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        grade = get_object_or_404(
            grade_queryset().filter(team__adviser=request.user),
            pk=grade_id,
        )
        StudentTeam.objects.select_for_update().get(pk=grade.team_id)
        grade = resolve_canonical_capstone_grade(grade)
        if grade.schedule_id:
            DefenseSchedule.objects.select_for_update().get(pk=grade.schedule_id)
        grade = TeamGrade.objects.select_for_update(of=('self',)).select_related(
            'team', 'semester', 'schedule', 'defense_stage',
        ).get(pk=grade.pk)

        if grade.status in TeamGrade.LOCKED_STATUSES:
            return Response(
                {'detail': 'Grades for this team have already been finalized and cannot be changed.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            require_grade_editable(grade)
            reason = adviser_grading_unavailable_reason(grade)
            if reason:
                raise DjangoValidationError(reason)
        except DjangoValidationError as exc:
            return Response(
                {'detail': exc.message if hasattr(exc, 'message') else str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        grade = GradeContextService.get_for_adviser_context(request.user, grade)
        serializer = _AdviserGradeSubmitSerializer(
            data=request.data, context={'grade': grade}
        )
        serializer.is_valid(raise_exception=True)
        grade = serializer.save()
        payload = TeamGradeSerializer(grade).data
        payload.update(assigned_adviser_rubric_payload(grade))
        reason = adviser_grading_unavailable_reason(grade)
        payload.update(adviser_grading_available=not reason, adviser_grading_unavailable_reason=reason)
        return Response({'grade': payload})
