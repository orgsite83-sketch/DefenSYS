from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from defense.stages.models import DefenseStage
from defense.stages.serializers import DefenseStageSerializer
from user_management.permissions import IsSystemAdmin
from .models import TeamGrade
from .serializers import TeamGradeSerializer, TeamGradeUpdateSerializer
from django.core.exceptions import ValidationError as DjangoValidationError

from .services import (
    active_semester,
    build_group_settings_map,
    grade_queryset_for_user,
    group_settings_key,
    publish_grade_record,
    require_grade_editable,
    repair_pending_passed_grades_in_queryset,
    sync_missing_grade_rows,
    update_group_settings,
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


def _is_grade_center_admin(user):
    return bool(
        user
        and (
            getattr(user, 'role', None) == 'admin'
            or getattr(user, 'is_superuser', False)
        )
    )


def filter_grade_queryset(request, queryset):
    search = request.query_params.get('search', '').strip()
    year_level = request.query_params.get('year_level', '').strip()
    status_filter = request.query_params.get('status', '').strip()

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

    if 'scope' not in request.query_params:
        if _is_grade_center_admin(request.user):
            queryset = queryset.filter(scope=TeamGrade.SCOPE_CAPSTONE)
    else:
        scope = request.query_params.get('scope', '').strip()
        if scope and scope != 'all':
            queryset = queryset.filter(scope=scope)

    return queryset


def counts_payload(base_queryset, current_queryset=None):
    current = current_queryset if current_queryset is not None else base_queryset
    return {
        'all': base_queryset.count(),
        'filtered': current.count(),
        'published': current.filter(status=TeamGrade.STATUS_PUBLISHED).count(),
        'ready_for_archive': current.filter(status=TeamGrade.STATUS_READY_FOR_ARCHIVE).count(),
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


def refresh_peer_summaries_in_queryset(queryset):
    """Rebuild peer aggregates for grades that already have submissions."""
    from .peer_eval import sync_peer_summaries
    from .services import resolve_canonical_capstone_grade

    grades_with_submissions = queryset.filter(
        peer_evaluation_submissions__isnull=False,
    ).distinct()
    for grade in grades_with_submissions:
        if grade.scope == TeamGrade.SCOPE_CAPSTONE:
            grade = resolve_canonical_capstone_grade(grade)
        sync_peer_summaries(grade)


def grade_center_payload(request, queryset=None, sync_info=None):
    base = grade_queryset_for_user(request.user)
    current = queryset if queryset is not None else base
    semester = active_semester()
    payload = {
        'grades': TeamGradeSerializer(current, many=True).data,
        'counts': counts_payload(base, current),
        'active_semester': SemesterSerializer(semester).data if semester else None,
        'group_settings': build_group_settings_map(current, semester),
        **options_payload(base),
    }
    if CanManageGradeCenter().has_permission(request, None):
        active_stages = list(
            DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label')
        )
        payload['capstone_stages'] = DefenseStageSerializer(
            active_stages,
            many=True,
            context={'ordered_stages': active_stages},
        ).data
    if sync_info is not None:
        payload['sync'] = sync_info
    return payload


class GradeCenterListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        sync_missing_grade_rows(user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        refresh_peer_summaries_in_queryset(queryset)
        repair_pending_passed_grades_in_queryset(queryset, user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        return Response(grade_center_payload(request, queryset))


class GradeCenterSyncView(APIView):
    permission_classes = [CanManageGradeCenter]

    def post(self, request):
        sync_info = sync_missing_grade_rows(user=request.user)
        queryset = filter_grade_queryset(request, grade_queryset_for_user(request.user))
        return Response(grade_center_payload(request, queryset, sync_info=sync_info))


class GradeCenterDetailView(APIView):
    permission_classes = [CanManageGradeCenter]

    def get_object(self, request, grade_id):
        return get_object_or_404(grade_queryset_for_user(request.user), pk=grade_id)

    def get(self, request, grade_id):
        sync_missing_grade_rows(user=request.user)
        grade = self.get_object(request, grade_id)
        if grade.peer_evaluation_submissions.exists():
            from .peer_eval import sync_peer_summaries
            from .services import resolve_canonical_capstone_grade

            if grade.scope == TeamGrade.SCOPE_CAPSTONE:
                grade = resolve_canonical_capstone_grade(grade)
            sync_peer_summaries(grade)
            grade = grade_queryset_for_user(request.user).get(pk=grade.pk)
        return Response({'grade': TeamGradeSerializer(grade).data})

    def patch(self, request, grade_id):
        grade = self.get_object(request, grade_id)
        try:
            require_grade_editable(grade)
        except DjangoValidationError as exc:
            return Response(
                {'detail': exc.messages[0] if getattr(exc, 'messages', None) else str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
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
        try:
            require_grade_editable(grade)
        except DjangoValidationError as exc:
            return Response(
                {'detail': exc.messages[0] if getattr(exc, 'messages', None) else str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
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
            from realtime.broadcast import notify_capstone_evaluation_flags

            notify_capstone_evaluation_flags(
                semester,
                peer_eval_enabled=semester.capstone_peer_evaluation_enabled
                if 'capstone_peer_evaluation_enabled' in update_fields
                else None,
                adviser_grading_enabled=semester.capstone_adviser_grading_enabled
                if 'capstone_adviser_grading_enabled' in update_fields
                else None,
            )
        return Response({'active_semester': SemesterSerializer(semester).data})


class GradeCenterGroupSettingsSerializer(drf_serializers.Serializer):
    scope = drf_serializers.ChoiceField(choices=[TeamGrade.SCOPE_CAPSTONE, TeamGrade.SCOPE_PIT])
    stage_label = drf_serializers.CharField(max_length=120)
    is_officially_complete = drf_serializers.BooleanField(required=False)
    peer_grading_enabled = drf_serializers.BooleanField(required=False)

    def validate(self, attrs):
        if 'is_officially_complete' not in attrs and 'peer_grading_enabled' not in attrs:
            raise drf_serializers.ValidationError('At least one setting field is required.')
        return attrs


class GradeCenterGroupSettingsView(APIView):
    permission_classes = [CanManageGradeCenter]

    def patch(self, request):
        semester = active_semester()
        if semester is None:
            return Response(
                {'detail': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = GradeCenterGroupSettingsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            settings = update_group_settings(
                semester=semester,
                scope=data['scope'],
                stage_label=data['stage_label'],
                is_officially_complete=data.get('is_officially_complete'),
                peer_grading_enabled=data.get('peer_grading_enabled'),
                user=request.user,
            )
        except DjangoValidationError as exc:
            payload = exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)

        key = group_settings_key(data['scope'], data['stage_label'])
        response_payload = {'group_settings': {key: settings}}
        auto_publish = settings.get('auto_publish')
        if auto_publish:
            response_payload['auto_publish'] = auto_publish
        auto_finalize = settings.get('auto_finalize')
        if auto_finalize:
            response_payload['auto_finalize'] = auto_finalize
        return Response(response_payload)
