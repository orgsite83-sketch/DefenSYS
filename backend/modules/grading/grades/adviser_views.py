from decimal import Decimal

from django.core.exceptions import ValidationError as DjangoValidationError
from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from grading.rubrics.models import Rubric
from .models import GradeBreakdown, StudentStageGrade, TeamGrade
from .peer_eval import recalculate_student_grade
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

        GradeBreakdown.objects.filter(
            team_grade=grade, evaluation_type=GradeBreakdown.EVAL_ADVISER
        ).delete()

        breakdowns = []
        student_adviser_scores = {}

        if target_type == Rubric.TARGET_INDIVIDUAL:
            if not student_submissions:
                raise drf_serializers.ValidationError(
                    {'student_submissions': 'Student submissions are required for individual adviser rubrics.'}
                )
            for sub in student_submissions:
                s_id = sub.get('student_id')
                student_user = student_map.get(s_id)
                if not student_user:
                    continue
                s_scores = sub.get('criteria_scores', [])
                total_s = Decimal('0')
                max_s = Decimal('0')
                for idx, cs in enumerate(s_scores):
                    try:
                        s_val = Decimal(str(cs.get('score', 0)))
                        m_val = Decimal(str(cs.get('max_score', 10)))
                    except Exception:
                        s_val = Decimal('0')
                        m_val = Decimal('10')
                    total_s += s_val
                    max_s += m_val
                    breakdowns.append(
                        GradeBreakdown(
                            team_grade=grade,
                            student=student_user,
                            rubric=rubric,
                            evaluation_type=GradeBreakdown.EVAL_ADVISER,
                            criterion_name=str(cs.get('criterion_name', '')),
                            score=s_val,
                            max_score=m_val,
                            display_order=int(cs.get('display_order', idx)),
                        )
                    )
                if max_s > 0:
                    student_adviser_scores[s_id] = (total_s / max_s * Decimal('100')).quantize(Decimal('0.01'))
                else:
                    student_adviser_scores[s_id] = Decimal('0.00')

        elif target_type == Rubric.TARGET_BOTH:
            team_total = Decimal('0')
            team_max = Decimal('0')
            for idx, cs in enumerate(team_criteria_scores):
                try:
                    s_val = Decimal(str(cs.get('score', 0)))
                    m_val = Decimal(str(cs.get('max_score', 10)))
                except Exception:
                    s_val = Decimal('0')
                    m_val = Decimal('10')
                team_total += s_val
                team_max += m_val
                breakdowns.append(
                    GradeBreakdown(
                        team_grade=grade,
                        student=None,
                        rubric=rubric,
                        evaluation_type=GradeBreakdown.EVAL_ADVISER,
                        criterion_name=str(cs.get('criterion_name', '')),
                        score=s_val,
                        max_score=m_val,
                        display_order=int(cs.get('display_order', idx)),
                    )
                )

            sub_map = {s.get('student_id'): s.get('criteria_scores', []) for s in student_submissions}
            for m in memberships:
                s_id = m.student_id
                s_scores = sub_map.get(s_id, [])
                ind_total = Decimal('0')
                ind_max = Decimal('0')
                for idx, cs in enumerate(s_scores):
                    try:
                        s_val = Decimal(str(cs.get('score', 0)))
                        m_val = Decimal(str(cs.get('max_score', 10)))
                    except Exception:
                        s_val = Decimal('0')
                        m_val = Decimal('10')
                    ind_total += s_val
                    ind_max += m_val
                    breakdowns.append(
                        GradeBreakdown(
                            team_grade=grade,
                            student=m.student,
                            rubric=rubric,
                            evaluation_type=GradeBreakdown.EVAL_ADVISER,
                            criterion_name=str(cs.get('criterion_name', '')),
                            score=s_val,
                            max_score=m_val,
                            display_order=int(cs.get('display_order', idx)),
                        )
                    )
                combined_total = team_total + ind_total
                combined_max = team_max + ind_max
                if combined_max > 0:
                    student_adviser_scores[s_id] = (combined_total / combined_max * Decimal('100')).quantize(Decimal('0.01'))
                else:
                    student_adviser_scores[s_id] = Decimal('0.00')

        else:  # Rubric.TARGET_TEAM
            if not team_criteria_scores:
                raise drf_serializers.ValidationError(
                    {'criteria_scores': 'Criteria scores are required for adviser grading.'}
                )
            team_total = Decimal('0')
            team_max = Decimal('0')
            for idx, cs in enumerate(team_criteria_scores):
                try:
                    s_val = Decimal(str(cs.get('score', 0)))
                    m_val = Decimal(str(cs.get('max_score', 10)))
                except Exception:
                    s_val = Decimal('0')
                    m_val = Decimal('10')
                team_total += s_val
                team_max += m_val
                breakdowns.append(
                    GradeBreakdown(
                        team_grade=grade,
                        student=None,
                        rubric=rubric,
                        evaluation_type=GradeBreakdown.EVAL_ADVISER,
                        criterion_name=str(cs.get('criterion_name', '')),
                        score=s_val,
                        max_score=m_val,
                        display_order=int(cs.get('display_order', idx)),
                    )
                )
            if team_max > 0:
                team_score = (team_total / team_max * Decimal('100')).quantize(Decimal('0.01'))
            else:
                team_score = self.validated_data.get('adviser_score') or Decimal('0.00')
            for m in memberships:
                student_adviser_scores[m.student_id] = team_score

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
        elif self.validated_data.get('adviser_score') is not None:
            grade.adviser_score = self.validated_data['adviser_score']

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
