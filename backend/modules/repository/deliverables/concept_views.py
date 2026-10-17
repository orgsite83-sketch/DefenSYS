from django.db import transaction
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView
from .views import (CanManageDeliverables, get_allowed_team, check_deliverable_write_permission,
                    deliverable_error_response, deliverables_action_payload)
from . import concepts


class ConceptActionSerializer(serializers.Serializer):
    team_id = serializers.IntegerField(min_value=1)
    stage_label = serializers.CharField(max_length=120)
    action = serializers.ChoiceField(choices=['save_titles', 'override_clearance'])
    concepts = serializers.ListField(child=serializers.DictField(), required=False)
    reason = serializers.CharField(required=False, max_length=5000, allow_blank=True)


class ConceptActionView(APIView):
    permission_classes = [CanManageDeliverables]

    @transaction.atomic
    def post(self, request):
        data = ConceptActionSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        attrs = data.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        if not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You cannot manage this team’s concepts.'}, status=403)
        stage = concepts.stage_for(team, attrs['stage_label'])
        if not concepts.enabled(stage):
            return Response({'detail': 'Concept selection is not enabled for this stage.'}, status=400)
        if not team.semester.is_active:
            return Response({'detail': 'Historical concept rounds are read-only.'}, status=403)
        try:
            if attrs['action'] == 'save_titles':
                concepts.save_titles(team, stage, attrs.get('concepts'))
            else:
                concepts.override_clearance(team, stage, request.user, attrs.get('reason', ''))
        except (ValueError, PermissionError, concepts.ValidationError) as exc:
            return deliverable_error_response(exc)
        return Response(deliverables_action_payload(request, team, stage.label))
