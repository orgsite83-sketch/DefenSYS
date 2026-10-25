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
    action = serializers.ChoiceField(choices=['save_titles', 'save_draft_titles', 'override_clearance', 'pit_decision', 'clear_pit_revisions'])
    concepts = serializers.ListField(child=serializers.DictField(), required=False)
    reason = serializers.CharField(required=False, max_length=5000, allow_blank=True)
    review_token = serializers.CharField(required=False, max_length=64)


class ConceptActionView(APIView):
    permission_classes = [CanManageDeliverables]

    def get(self, request):
        team_id = serializers.IntegerField(min_value=1).run_validation(request.query_params.get('team_id'))
        label = serializers.CharField(max_length=120).run_validation(request.query_params.get('stage_label'))
        team = get_allowed_team(request, team_id)
        stage = concepts.stage_for(team, label)
        if not concepts.enabled(stage):
            return Response({'detail': 'Concept selection is not enabled for this stage.'}, status=400)
        workflow = concepts.payload(team, stage, actor=request.user)
        leader = request.user.role == 'student' and team.leader_id == request.user.pk
        workflow['can_edit_titles'] = bool(workflow['can_edit_titles'] and leader and
            workflow['status'] not in ('scheduled', 'approved', 'approved_with_revisions', 'failed', 'project_rejected', 'for_redefense') and
            not workflow.get('module_names_confirmed'))
        return Response({'team_id': team.pk, 'stage_label': stage.label, 'concept_workflow': workflow})

    @transaction.atomic
    def post(self, request):
        data = ConceptActionSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        attrs = data.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        if attrs['action'] in ('pit_decision', 'clear_pit_revisions'):
            from .pit_decisions import can_manage
            if not can_manage(request.user, team):
                return Response({'detail': 'You cannot manage this team’s concepts.'}, status=403)
        elif not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You cannot manage this team’s concepts.'}, status=403)
        stage = concepts.stage_for(team, attrs['stage_label'])
        if not concepts.enabled(stage):
            return Response({'detail': 'Concept selection is not enabled for this stage.'}, status=400)
        if not team.semester.is_active:
            return Response({'detail': 'Historical concept rounds are read-only.'}, status=403)
        try:
            if attrs['action'] in ('save_titles', 'save_draft_titles'):
                from student_teams.models import StudentTeam
                team = StudentTeam.objects.select_for_update().get(pk=team.pk)
                draft = attrs['action'] == 'save_draft_titles'
                if draft and (request.user.role != 'student' or team.leader_id != request.user.pk):
                    return Response({'detail': 'Only the team leader can save title drafts.'}, status=403)
                if draft and not attrs.get('review_token'):
                    return Response({'detail': 'Reload the current concepts before saving a draft.'}, status=409)
                if attrs.get('review_token') and attrs['review_token'] != concepts.module_review_token(team, stage):
                    return Response({'detail': 'The module names or system connections changed. Refresh and review the current names.'}, status=409)
                concepts.save_titles(team, stage, attrs.get('concepts'), actor=request.user, draft=draft)
            elif attrs['action'] in ('pit_decision', 'clear_pit_revisions'):
                current = concepts.latest_round(team, stage)
                if current and current.section_round_id and not request.data.get('module_review'):
                    raise concepts.ValidationError('Module decisions for a shared section system must be managed in the shared section workspace.')
                from .pit_decisions import record_decision
                record_decision(team, stage, request.user, attrs.get('concepts'),
                    token=attrs.get('review_token'), reason=attrs.get('reason', ''),
                    clear_revisions=attrs['action'] == 'clear_pit_revisions')
                team.refresh_from_db()
            else:
                concepts.override_clearance(team, stage, request.user, attrs.get('reason', ''))
        except PermissionError as exc:
            if attrs['action'] in ('pit_decision', 'clear_pit_revisions'):
                return Response({'detail': str(exc)}, status=403)
            return deliverable_error_response(exc)
        except (ValueError, concepts.ValidationError) as exc:
            return deliverable_error_response(exc)
        if request.query_params.get('response_mode') == 'concept_titles':
            return Response({'team_id': team.pk, 'stage_label': stage.label,
                'concept_workflow': concepts.payload(team, stage, actor=request.user)})
        return Response(deliverables_action_payload(request, team, stage.label))
