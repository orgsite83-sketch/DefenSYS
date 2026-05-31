from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from defense.stages.models import DefenseStage
from defense.stages.serializers import DefenseStageSerializer
from .models import Rubric
from .serializers import RubricSerializer, RubricWeightsSerializer, RubricWriteSerializer


class CanManageRubrics(BasePermission):
    message = 'Only administrators and PIT leads can manage rubrics.'

    def has_permission(self, request, view):
        return user_can_manage_rubrics(request.user)


def user_can_manage_rubrics(user):
    if not user or not user.is_authenticated:
        return False
    return bool(
        getattr(user, 'role', None) == 'admin'
        or user.is_superuser
        or getattr(user, 'is_pit_lead', False)
    )


def _is_pit_lead_only(user):
    return bool(
        user
        and user.is_authenticated
        and getattr(user, 'is_pit_lead', False)
        and getattr(user, 'role', None) != 'admin'
        and not getattr(user, 'is_superuser', False)
    )


def _is_capstone_only_manager(user):
    if not user or not user.is_authenticated or _is_pit_lead_only(user):
        return False
    return bool(
        getattr(user, 'role', None) == 'admin'
        or getattr(user, 'is_superuser', False)
    )


def rubric_queryset_for_read(user):
    base = rubric_queryset()
    if _is_pit_lead_only(user):
        return base.filter(created_by=user)
    if user_can_manage_rubrics(user):
        return base
    return base.filter(status=Rubric.STATUS_PUBLISHED)


def rubric_queryset_for_manage(user):
    return rubric_queryset_for_read(user)


def list_payload_for_request(request):
    visible = rubric_queryset_for_read(request.user)
    filtered = filter_rubrics(request, visible, apply_evaluation_type=True)
    counts_queryset = filter_rubrics(request, visible, apply_evaluation_type=False)
    return list_payload(
        filtered,
        stats_base=visible,
        counts_queryset=counts_queryset,
        user=request.user,
    )


def rubric_queryset():
    return (
        Rubric.objects.select_related(
            'semester',
            'semester__school_year',
            'defense_stage',
            'created_by',
        )
        .prefetch_related('criteria')
    )


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def _scopes_for_user(user):
    all_scopes = [
        {'value': key, 'label': label}
        for key, label in Rubric.SCOPE_CHOICES
    ]
    if user is None:
        return all_scopes
    if _is_pit_lead_only(user):
        return [item for item in all_scopes if item['value'] == Rubric.SCOPE_PIT]
    if _is_capstone_only_manager(user):
        return [item for item in all_scopes if item['value'] == Rubric.SCOPE_CAPSTONE]
    return all_scopes


def options_payload(user=None):
    semesters = Semester.objects.select_related('school_year').order_by('-school_year__label', 'label')
    stages = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label')
    return {
        'active_semester': SemesterSerializer(active_semester()).data if active_semester() else None,
        'semesters': SemesterSerializer(semesters, many=True).data,
        'defense_stages': DefenseStageSerializer(stages, many=True).data,
        'scopes': _scopes_for_user(user),
        'evaluation_types': [
            {'value': key, 'label': label}
            for key, label in Rubric.EVALUATION_TYPE_CHOICES
        ],
        'scale_options': [choice[0] for choice in Rubric.SCALE_CHOICES],
        'statuses': [choice[0] for choice in Rubric.STATUS_CHOICES],
        'default_weights': {
            'capstone': {'panel': 50, 'adviser': 30, 'peer': 20},
            'pit': {'panel': 80, 'peer': 20},
        },
    }


def counts_payload(queryset=None, stats_base=None):
    base = stats_base if stats_base is not None else rubric_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'draft': current.filter(status=Rubric.STATUS_DRAFT).count(),
        'published': current.filter(status=Rubric.STATUS_PUBLISHED).count(),
        'locked': current.filter(is_locked=True).count(),
        'capstone': current.filter(scope=Rubric.SCOPE_CAPSTONE).count(),
        'pit': current.filter(scope=Rubric.SCOPE_PIT).count(),
        'eval_panel': current.filter(evaluation_type=Rubric.EVAL_PANEL).count(),
        'eval_adviser': current.filter(evaluation_type=Rubric.EVAL_ADVISER).count(),
        'eval_peer': current.filter(evaluation_type=Rubric.EVAL_PEER).count(),
    }


def list_payload(queryset=None, stats_base=None, counts_queryset=None, user=None):
    current = queryset if queryset is not None else rubric_queryset()
    base = stats_base if stats_base is not None else rubric_queryset()
    count_source = counts_queryset if counts_queryset is not None else current
    return {
        'rubrics': RubricSerializer(current, many=True).data,
        'counts': counts_payload(count_source, stats_base=base),
        **options_payload(user),
    }


def filter_rubrics(request, queryset=None, *, apply_evaluation_type=True):
    queryset = queryset if queryset is not None else rubric_queryset()
    search = request.query_params.get('search', '').strip()
    scope = request.query_params.get('scope', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    evaluation_type = request.query_params.get('evaluation_type', '').strip()

    if search:
        queryset = queryset.filter(
            Q(name__icontains=search)
            | Q(event_name__icontains=search)
            | Q(defense_stage__label__icontains=search)
            | Q(semester__school_year__label__icontains=search)
            | Q(semester__label__icontains=search)
        )
    if scope:
        queryset = queryset.filter(scope=scope)
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    if apply_evaluation_type and evaluation_type:
        queryset = queryset.filter(evaluation_type=evaluation_type)
    return queryset


class RubricListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageRubrics()]

    def get(self, request):
        visible = rubric_queryset_for_read(request.user)
        filtered = filter_rubrics(request, visible, apply_evaluation_type=True)
        counts_queryset = filter_rubrics(request, visible, apply_evaluation_type=False)
        return Response(
            list_payload(
                filtered,
                stats_base=visible,
                counts_queryset=counts_queryset,
                user=request.user,
            ),
        )

    def post(self, request):
        serializer = RubricWriteSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)

        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='rubric.create',
            target=rubric,
            new_values={
                'name': rubric.name,
                'scope': rubric.scope,
                'evaluation_type': rubric.evaluation_type,
                'semester': rubric.semester.display_name,
            },
            request=request,
        )

        return Response(
            {
                'rubric': RubricSerializer(rubric).data,
                **list_payload_for_request(request),
            },
            status=status.HTTP_201_CREATED,
        )


class RubricDetailView(APIView):
    permission_classes = [CanManageRubrics]

    def get_object(self, request, rubric_id):
        return get_object_or_404(
            rubric_queryset_for_manage(request.user),
            pk=rubric_id,
        )

    def patch(self, request, rubric_id):
        rubric = self.get_object(request, rubric_id)
        old_values = {
            'name': rubric.name,
            'scope': rubric.scope,
            'evaluation_type': rubric.evaluation_type,
            'semester': rubric.semester.display_name,
        }
        serializer = RubricWriteSerializer(
            rubric,
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)

        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='rubric.update',
            target=rubric,
            old_values=old_values,
            new_values={
                'name': rubric.name,
                'scope': rubric.scope,
                'evaluation_type': rubric.evaluation_type,
                'semester': rubric.semester.display_name,
            },
            request=request,
        )

        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload_for_request(request),
        })

    def delete(self, request, rubric_id):
        rubric = self.get_object(request, rubric_id)
        old_values = {
            'name': rubric.name,
            'scope': rubric.scope,
            'evaluation_type': rubric.evaluation_type,
            'semester': rubric.semester.display_name,
        }
        rubric_pk = rubric.pk
        rubric.delete()

        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='rubric.delete',
            target=rubric,
            target_type='Rubric',
            target_id=rubric_pk,
            old_values=old_values,
            new_values={'deleted': True},
            request=request,
        )

        return Response(list_payload_for_request(request), status=status.HTTP_200_OK)


class RubricPublishView(APIView):
    permission_classes = [CanManageRubrics]

    def post(self, request, rubric_id):
        rubric = get_object_or_404(
            rubric_queryset_for_manage(request.user),
            pk=rubric_id,
        )
        if rubric.criteria.count() == 0:
            return Response(
                {'criteria': 'At least one criterion is required before publishing.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        old_status = rubric.status
        rubric.status = Rubric.STATUS_PUBLISHED
        rubric.is_locked = True
        rubric.save()
        rubric = rubric_queryset().get(pk=rubric.pk)

        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='rubric.publish',
            target=rubric,
            old_values={'status': old_status, 'is_locked': False},
            new_values={'status': rubric.status, 'is_locked': True},
            request=request,
        )
        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload_for_request(request),
        })


class RubricWeightsView(APIView):
    permission_classes = [CanManageRubrics]

    def patch(self, request, rubric_id):
        rubric = get_object_or_404(
            rubric_queryset_for_manage(request.user),
            pk=rubric_id,
        )
        if rubric.scope == Rubric.SCOPE_CAPSTONE:
            return Response(
                {
                    'detail': (
                        'Capstone grade weights are configured per defense stage. '
                        'Open Defense Stages and edit the stage to adjust Panel / Adviser / Peer weights.'
                    ),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        if rubric.scope == Rubric.SCOPE_PIT:
            return Response(
                {
                    'detail': (
                        'PIT grade split is configured per event on Defense Scheduler '
                        '(panel rubric, peer rubric, and panel % / peer %).'
                    ),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = RubricWeightsSerializer(
            data=request.data,
            context={'rubric': rubric},
        )
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)
        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload_for_request(request),
        })
