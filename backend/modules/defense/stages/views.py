from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from user_management.permissions import IsSystemAdmin
from .grading_config import (
    get_or_create_stage_grading_config,
    grading_config_payload,
    resolve_semester,
)
from .models import DefenseStage, StageDeliverable
from .serializers import (
    DefenseStageSerializer,
    DefenseStageWriteSerializer,
    StageDeliverableSerializer,
    StageGradingConfigSerializer,
    StageGradingConfigWriteSerializer,
)


def normalize_stage_orders():
    """Ensure all defense stages have contiguous, unique display_order values (1, 2, 3...)."""
    stages = list(DefenseStage.objects.all().order_by('display_order', 'id'))
    with transaction.atomic():
        for index, stage in enumerate(stages, start=1):
            if stage.display_order != index:
                DefenseStage.objects.filter(pk=stage.pk).update(display_order=index)


def ordered_stages(include_inactive=True):
    normalize_stage_orders()
    queryset = DefenseStage.objects.all()
    if not include_inactive:
        queryset = queryset.filter(is_active=True)
    return list(queryset.order_by('display_order', 'id'))


def counts_payload():
    stages = DefenseStage.objects.all()
    return {
        'total': stages.count(),
        'active': stages.filter(is_active=True).count(),
        'inactive': stages.filter(is_active=False).count(),
    }


def stage_list_payload():
    stages = ordered_stages()
    active = [stage for stage in stages if stage.is_active]
    return {
        'stages': DefenseStageSerializer(
            stages,
            many=True,
            context={'ordered_stages': stages},
        ).data,
        'active_stages': DefenseStageSerializer(
            active,
            many=True,
            context={'ordered_stages': active},
        ).data,
        'counts': counts_payload(),
    }


class DefenseStageListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [IsSystemAdmin()]

    def get(self, request):
        return Response(stage_list_payload())

    def post(self, request):
        serializer = DefenseStageWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        with transaction.atomic():
            stage = serializer.save()
            # If a specific display_order was requested, place it and re-normalize
            requested_order = serializer.validated_data.get('display_order')
            all_stages = list(DefenseStage.objects.exclude(pk=stage.pk).order_by('display_order', 'id'))
            if requested_order is not None:
                insert_idx = max(0, min(requested_order - 1, len(all_stages)))
                all_stages.insert(insert_idx, stage)
            else:
                all_stages.append(stage)
            
            for index, s in enumerate(all_stages, start=1):
                DefenseStage.objects.filter(pk=s.pk).update(display_order=index)
            stage.refresh_from_db()

        return Response(
            {
                'stage': DefenseStageSerializer(
                    stage,
                    context={'ordered_stages': ordered_stages()},
                ).data,
                **stage_list_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


def _stage_detail_payload(stage, request):
    semester = resolve_semester(request.query_params.get('semester_id'))
    config = get_or_create_stage_grading_config(stage, semester) if semester else None
    payload = {
        'stage': DefenseStageSerializer(
            stage,
            context={'ordered_stages': ordered_stages()},
        ).data,
    }
    if semester:
        payload['active_semester'] = SemesterSerializer(semester).data
        payload['grading_config'] = (
            StageGradingConfigSerializer(config).data if config else grading_config_payload(None)
        )
    return payload


class DefenseStageDetailView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [IsSystemAdmin()]

    def get_object(self, stage_id):
        return get_object_or_404(DefenseStage, pk=stage_id)

    def get(self, request, stage_id):
        stage = self.get_object(stage_id)
        return Response(_stage_detail_payload(stage, request))

    def patch(self, request, stage_id):
        stage = self.get_object(stage_id)
        serializer = DefenseStageWriteSerializer(stage, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            old_order = stage.display_order
            stage = serializer.save()
            new_order = serializer.validated_data.get('display_order')

            if new_order is not None and new_order != old_order:
                other_stages = list(DefenseStage.objects.exclude(pk=stage.pk).order_by('display_order', 'id'))
                insert_idx = max(0, min(new_order - 1, len(other_stages)))
                other_stages.insert(insert_idx, stage)
                for index, s in enumerate(other_stages, start=1):
                    DefenseStage.objects.filter(pk=s.pk).update(display_order=index)
                stage.refresh_from_db()
            else:
                normalize_stage_orders()
                stage.refresh_from_db()

        return Response({
            'stage': DefenseStageSerializer(
                stage,
                context={'ordered_stages': ordered_stages()},
            ).data,
            **stage_list_payload(),
        })

    def delete(self, request, stage_id):
        from django.db.models import ProtectedError
        from .serializers import check_stage_locked

        stage = self.get_object(stage_id)
        locked, reason = check_stage_locked(stage)
        if locked:
            return Response(
                {
                    'warning': reason or 'This stage is locked and cannot be deleted.',
                },
                status=status.HTTP_409_CONFLICT,
            )
        try:
            with transaction.atomic():
                stage.delete()
                normalize_stage_orders()
        except ProtectedError:
            return Response(
                {
                    'warning': (
                        'This stage cannot be deleted because it has existing '
                        'schedules, grades, or team progress records linked to it.'
                    ),
                },
                status=status.HTTP_409_CONFLICT,
            )
        return Response(stage_list_payload(), status=status.HTTP_200_OK)


class DefenseStageReorderView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        stage_ids = request.data.get('stage_ids')
        if not isinstance(stage_ids, list) or len(stage_ids) == 0:
            return Response(
                {'stage_ids': 'A non-empty list of stage IDs is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing_stages = {s.id: s for s in DefenseStage.objects.all()}
        # Check all IDs provided exist
        for sid in stage_ids:
            if sid not in existing_stages:
                return Response(
                    {'stage_ids': f'Stage with ID {sid} does not exist.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        with transaction.atomic():
            # Update provided stages in given order
            assigned_order = 1
            for sid in stage_ids:
                DefenseStage.objects.filter(pk=sid).update(display_order=assigned_order)
                assigned_order += 1

            # If any stages were not included in stage_ids, put them at the end
            for sid in existing_stages:
                if sid not in stage_ids:
                    DefenseStage.objects.filter(pk=sid).update(display_order=assigned_order)
                    assigned_order += 1

        return Response(stage_list_payload(), status=status.HTTP_200_OK)


class StageDeliverableListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request, stage_id):
        from .serializers import check_stage_locked

        stage = get_object_or_404(DefenseStage, pk=stage_id)
        locked, reason = check_stage_locked(stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be added because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = StageDeliverableSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        deliverable = serializer.save(defense_stage=stage)
        return Response(
            StageDeliverableSerializer(deliverable).data,
            status=status.HTTP_201_CREATED,
        )


class StageDeliverableDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def patch(self, request, stage_id, deliverable_id):
        from .serializers import check_stage_locked

        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
        )
        locked, reason = check_stage_locked(deliverable.defense_stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be updated because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = StageDeliverableSerializer(
            deliverable,
            data=request.data,
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        deliverable = serializer.save()
        return Response(StageDeliverableSerializer(deliverable).data)

    def delete(self, request, stage_id, deliverable_id):
        from .serializers import check_stage_locked

        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
        )
        locked, reason = check_stage_locked(deliverable.defense_stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be deleted because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        deliverable.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class StageGradingConfigView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, stage_id):
        stage = get_object_or_404(DefenseStage, pk=stage_id)
        semester = resolve_semester(request.query_params.get('semester_id'))
        if semester is None:
            return Response(
                {'semester_id': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        config = get_or_create_stage_grading_config(stage, semester)
        return Response({
            'grading_config': StageGradingConfigSerializer(config).data,
            'active_semester': SemesterSerializer(semester).data,
        })

    def patch(self, request, stage_id):
        stage = get_object_or_404(DefenseStage, pk=stage_id)
        semester = resolve_semester(request.query_params.get('semester_id'))
        if semester is None:
            return Response(
                {'semester_id': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        config = get_or_create_stage_grading_config(stage, semester)
        serializer = StageGradingConfigWriteSerializer(
            data=request.data,
            context={'config': config},
        )
        serializer.is_valid(raise_exception=True)
        config = serializer.save()
        return Response({
            'grading_config': StageGradingConfigSerializer(config).data,
            'active_semester': SemesterSerializer(semester).data,
        })
