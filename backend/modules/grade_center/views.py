from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from defensys_backend.prototype_tools import require_prototype_tools
from user_management.permissions import IsSystemAdmin
from .models import TeamGrade
from .serializers import TeamGradeSerializer, TeamGradeUpdateSerializer
from .services import (
    active_semester,
    demo_fill_capstone_grades,
    grade_queryset_for_user,
    publish_grade_record,
    sync_missing_grade_rows,
)


class CanManageGradeCenter(BasePermission):
    message = 'Only administrators and PIT leads can manage grade records.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (
                getattr(user, 'role', None) == 'admin'
                or user.is_superuser
                or getattr(user, 'is_pit_lead', False)
            )
        )


def filter_grade_queryset(request, queryset):
    search = request.query_params.get('search', '').strip()
    year_level = request.query_params.get('year_level', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    scope = request.query_params.get('scope', '').strip()

    if search:
        queryset = queryset.filter(
            Q(team__name__icontains=search)
            | Q(team__project_title__icontains=search)
            | Q(stage_label__icontains=search)
            | Q(team__adviser__first_name__icontains=search)
            | Q(team__adviser__last_name__icontains=search)
            | Q(team__adviser__username__icontains=search)
            | Q(schedule__panel_assignments__panelist__first_name__icontains=search)
            | Q(schedule__panel_assignments__panelist__last_name__icontains=search)
            | Q(schedule__panel_assignments__panelist__username__icontains=search)
        ).distinct()
    if year_level:
        queryset = queryset.filter(team__year_level=year_level)
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    if scope:
        queryset = queryset.filter(scope=scope)
    return queryset


def counts_payload(base_queryset, current_queryset=None):
    current = current_queryset if current_queryset is not None else base_queryset
    return {
        'all': base_queryset.count(),
        'filtered': current.count(),
        'published': current.filter(status=TeamGrade.STATUS_PUBLISHED).count(),
        'pending': current.filter(status=TeamGrade.STATUS_PENDING).count(),
        'awaiting_peers': current.filter(status=TeamGrade.STATUS_AWAITING_PEERS).count(),
        'passed': current.filter(final_grade__gte=75).count(),
        'failed': current.filter(final_grade__lt=75, final_grade__isnull=False).count(),
        'capstone': current.filter(scope=TeamGrade.SCOPE_CAPSTONE).count(),
        'pit': current.filter(scope=TeamGrade.SCOPE_PIT).count(),
    }


def options_payload(queryset):
    year_levels = [
        value
        for value in queryset.values_list('team__year_level', flat=True).distinct()
        if value
    ]
    return {
        'statuses': [choice[0] for choice in TeamGrade.STATUS_CHOICES],
        'year_levels': sorted(set(year_levels)),
        'scopes': [
            {'value': key, 'label': label}
            for key, label in TeamGrade.SCOPE_CHOICES
        ],
    }


def grade_center_payload(request, queryset=None, sync_info=None):
    base = grade_queryset_for_user(request.user)
    current = queryset if queryset is not None else base
    semester = active_semester()
    payload = {
        'grades': TeamGradeSerializer(current, many=True).data,
        'counts': counts_payload(base, current),
        'active_semester': SemesterSerializer(semester).data if semester else None,
        **options_payload(base),
    }
    if sync_info is not None:
        payload['sync'] = sync_info
    return payload


class GradeCenterListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        sync_missing_grade_rows(user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        return Response(grade_center_payload(request, queryset))


class GradeCenterSyncView(APIView):
    permission_classes = [CanManageGradeCenter]

    def post(self, request):
        sync_info = sync_missing_grade_rows(user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        return Response(grade_center_payload(request, queryset, sync_info=sync_info))


class GradeCenterDemoFillView(APIView):
    permission_classes = [CanManageGradeCenter]

    def post(self, request):
        require_prototype_tools()
        filled_count = demo_fill_capstone_grades(user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        return Response(
            {
                'filled_count': filled_count,
                **grade_center_payload(request, queryset),
            },
            status=status.HTTP_200_OK,
        )


class GradeCenterDetailView(APIView):
    permission_classes = [CanManageGradeCenter]

    def get_object(self, request, grade_id):
        return get_object_or_404(grade_queryset_for_user(request.user), pk=grade_id)

    def patch(self, request, grade_id):
        grade = self.get_object(request, grade_id)
        serializer = TeamGradeUpdateSerializer(data=request.data, context={'grade': grade})
        serializer.is_valid(raise_exception=True)
        grade = serializer.save()
        grade = grade_queryset_for_user(request.user).get(pk=grade.pk)
        return Response({
            'grade': TeamGradeSerializer(grade).data,
            **grade_center_payload(request),
        })


class GradeCenterPublishView(APIView):
    permission_classes = [CanManageGradeCenter]

    def post(self, request, grade_id):
        grade = get_object_or_404(grade_queryset_for_user(request.user), pk=grade_id)
        grade = publish_grade_record(grade, user=request.user)
        grade = grade_queryset_for_user(request.user).get(pk=grade.pk)
        return Response({
            'grade': TeamGradeSerializer(grade).data,
            **grade_center_payload(request),
        })


class CapstoneEvaluationSettingsSerializer(drf_serializers.Serializer):
    capstone_peer_evaluation_enabled = drf_serializers.BooleanField(required=False)
    capstone_adviser_grading_enabled = drf_serializers.BooleanField(required=False)


class CapstoneEvaluationSettingsView(APIView):
    permission_classes = [IsSystemAdmin]

    def patch(self, request):
        semester = active_semester()
        if semester is None:
            return Response(
                {'detail': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = CapstoneEvaluationSettingsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        update_fields = []
        if 'capstone_peer_evaluation_enabled' in data:
            semester.capstone_peer_evaluation_enabled = data['capstone_peer_evaluation_enabled']
            update_fields.append('capstone_peer_evaluation_enabled')
        if 'capstone_adviser_grading_enabled' in data:
            semester.capstone_adviser_grading_enabled = data['capstone_adviser_grading_enabled']
            update_fields.append('capstone_adviser_grading_enabled')
        if update_fields:
            semester.save(update_fields=update_fields)
        return Response({'active_semester': SemesterSerializer(semester).data})
