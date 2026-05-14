from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from user_management.permissions import IsSystemAdmin
from .models import DefenseStage, StageDeliverable
from .serializers import DefenseStageSerializer, DefenseStageWriteSerializer, StageDeliverableSerializer


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


class DefenseStageDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def get_object(self, stage_id):
        return get_object_or_404(DefenseStage, pk=stage_id)

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
        stage = self.get_object(stage_id)
        stage.delete()
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
