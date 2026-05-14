from decimal import Decimal

from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from rubric_engine.models import Rubric
from .models import GradeBreakdown, TeamGrade
from .serializers import TeamGradeSerializer
from .services import active_semester, grade_queryset, sync_missing_grade_rows


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
        grade.adviser_score = self.validated_data['adviser_score']

        rubric_id = self.validated_data.get('rubric_id')
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
            except Rubric.DoesNotExist:
                pass

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
        sync_missing_grade_rows(user=request.user)
        grades = (
            grade_queryset()
            .filter(team__adviser=request.user, scope=TeamGrade.SCOPE_CAPSTONE)
            .order_by('team__name', 'stage_label')
        )
        total = grades.count()
        graded = grades.filter(adviser_score__isnull=False).count()
        semester = active_semester()
        adviser_on = (
            getattr(semester, 'capstone_adviser_grading_enabled', True) if semester else True
        )
        return Response({
            'grades': TeamGradeSerializer(grades, many=True).data,
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
        serializer = _AdviserGradeSubmitSerializer(
            data=request.data, context={'grade': grade}
        )
        serializer.is_valid(raise_exception=True)
        grade = serializer.save()
        return Response({'grade': TeamGradeSerializer(grade).data})
