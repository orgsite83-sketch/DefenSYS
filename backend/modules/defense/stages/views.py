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


def ordered_stages(include_inactive=True):
    queryset = DefenseStage.objects.all()
    if not include_inactive:
        queryset = queryset.filter(is_active=True)
    return list(queryset.order_by('display_order', 'label'))


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
        stage = serializer.save()
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
        stage = serializer.save()

        return Response({
            'stage': DefenseStageSerializer(
                stage,
                context={'ordered_stages': ordered_stages()},
            ).data,
            **stage_list_payload(),
        })

    def delete(self, request, stage_id):
        from django.db.models import ProtectedError

        stage = self.get_object(stage_id)
        try:
            stage.delete()
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




class StageDeliverableListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request, stage_id):
        stage = get_object_or_404(DefenseStage, pk=stage_id)
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
        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
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
        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
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
