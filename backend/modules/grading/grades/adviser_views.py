from decimal import Decimal

from django.core.exceptions import ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from grading.rubrics.models import Rubric
from .models import GradeBreakdown, TeamGrade
from .serializers import TeamGradeSerializer
from .services import (
    GradeContextService,
    active_semester,
    adviser_capstone_grades_for_user,
    assigned_adviser_rubric_payload,
    grade_queryset,
    require_grade_editable,
    require_matching_rubric,
)


class _AdviserGradeSubmitSerializer(drf_serializers.Serializer):
    adviser_score = drf_serializers.DecimalField(
        max_digits=5, decimal_places=2, min_value=0, max_value=100
    )
    rubric_id = drf_serializers.IntegerField(required=False, allow_null=True)
    criteria_scores = drf_serializers.ListField(
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

        grade.adviser_score = self.validated_data['adviser_score']
        rubric_id = self.validated_data.get('rubric_id') or assigned.pk
        if rubric_id and assigned and rubric_id != assigned.pk:
            raise drf_serializers.ValidationError(
                {'rubric_id': 'Use the adviser rubric assigned for this defense stage.'}
            )
        criteria_scores = self.validated_data.get('criteria_scores') or []

        if rubric_id and criteria_scores:
            try:
                rubric = Rubric.objects.prefetch_related('criteria').get(
                    pk=rubric_id, evaluation_type=Rubric.EVAL_ADVISER
                )
                GradeBreakdown.objects.filter(
                    team_grade=grade, evaluation_type=GradeBreakdown.EVAL_ADVISER
                ).delete()
                breakdowns = []
                for idx, cs in enumerate(criteria_scores):
                    score_val = cs.get('score', 0)
                    max_val = cs.get('max_score', 10)
                    try:
                        score_val = Decimal(str(score_val))
                        max_val = Decimal(str(max_val))
                    except Exception:
                        score_val = Decimal('0')
                        max_val = Decimal('10')
                    breakdowns.append(
                        GradeBreakdown(
                            team_grade=grade,
                            rubric=rubric,
                            evaluation_type=GradeBreakdown.EVAL_ADVISER,
                            criterion_name=str(cs.get('criterion_name', '')),
                            score=score_val,
                            max_score=max_val,
                            display_order=int(cs.get('display_order', idx)),
                        )
                    )
                GradeBreakdown.objects.bulk_create(breakdowns)
            except Rubric.DoesNotExist as exc:
                raise drf_serializers.ValidationError(
                    {'rubric_id': 'Adviser rubric does not exist.'}
                ) from exc

        grade.save()
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
        grade = GradeContextService.get_for_adviser_context(request.user, grade)

        if grade.status in TeamGrade.LOCKED_STATUSES:
            return Response(
                {'detail': 'Grades for this team have already been finalized and cannot be changed.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            require_grade_editable(grade)
        except DjangoValidationError as exc:
            return Response(
                {'detail': exc.message if hasattr(exc, 'message') else str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = _AdviserGradeSubmitSerializer(
            data=request.data, context={'grade': grade}
        )
        serializer.is_valid(raise_exception=True)
        grade = serializer.save()
        payload = TeamGradeSerializer(grade).data
        payload.update(assigned_adviser_rubric_payload(grade))
        return Response({'grade': payload})
