from django.db import transaction, IntegrityError
from django.core.exceptions import ValidationError as ModelValidationError
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.exceptions import ValidationError

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from user_management.permissions import CanManageTeams
from . import formation
from .models import StudentTeam
from .term_scope import get_active_semester


class FormationRequest(serializers.Serializer):
    level = serializers.ChoiceField(choices=StudentTeam.LEVEL_CHOICES)
    event_name = serializers.CharField(required=False, allow_blank=True, max_length=120)
    sections = serializers.ListField(child=serializers.CharField(max_length=80), min_length=1, max_length=100)
    method = serializers.ChoiceField(choices=['random', 'alphabetical', 'reuse'])
    group_size = serializers.IntegerField(min_value=1, max_value=4)
    source_team_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), required=False, max_length=500)


class TeamDraft(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    section = serializers.CharField(max_length=80)
    leader_id = serializers.IntegerField(min_value=1)
    member_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=4)


class FormationCommitRequest(FormationRequest):
    preview_token = serializers.CharField(max_length=200000)
    teams = TeamDraft(many=True, allow_empty=False)


class TeamFormationView(APIView):
    permission_classes = [CanManageTeams]

    def get(self, request):
        return Response(formation.options(request.user, request.query_params))

    def post(self, request):
        data = FormationRequest(data=request.data)
        data.is_valid(raise_exception=True)
        return Response(formation.preview(request.user, data.validated_data))


class TeamFormationCommitView(APIView):
    permission_classes = [CanManageTeams]

    def post(self, request):
        data = FormationCommitRequest(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            teams = formation.create_from_preview(request, data.validated_data)
        except (IntegrityError, ModelValidationError) as exc:
            raise ValidationError('A team name or roster changed while saving. Refresh the preview and try again.') from exc
        return Response({'team_ids': [t.pk for t in teams], 'created_count': len(teams)}, status=201)


class PitTeamPolicyView(APIView):
    permission_classes = [CanManageTeams]

    def patch(self, request, event_id):
        policy = serializers.ChoiceField(choices=['single', 'multiple']).run_validation(
            request.data.get('team_membership_policy'))
        event = formation.update_event_policy(request, event_id, policy)
        return Response({'event_id': event.pk, 'team_membership_policy': event.team_membership_policy})


def setup_tasks(user):
    from .concept_policy import contexts_for, resolve_policy
    from repository.deliverables.concepts import latest_round, titles_complete
    teams = StudentTeam.objects.filter(semester=get_active_semester(), leader=user,
        memberships__student=user).distinct().order_by('name')
    result = []
    for team in teams:
        if not (team.setup_pending or team.project_pending):
            continue
        tasks = []
        for stage in contexts_for(team):
            if team.is_pit and team.current_defense_stage and stage.event_name != team.current_defense_stage:
                continue
            policy = resolve_policy(team, stage)
            if not titles_complete(latest_round(team, stage)):
                tasks.append({'stage_label': stage.label, 'required_count': policy['required_count'],
                              'mode': policy['mode']})
        if team.setup_pending or tasks:
            result.append({'id': team.pk, 'name': team.name, 'section': team.section,
                           'scope': 'pit' if team.is_pit else 'capstone', 'year_level': team.year_level,
                           'event_name': team.current_defense_stage or '',
                           'needs_name': team.setup_pending, 'concept_tasks': tasks})
    return result


class MyTeamSetupView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({'teams': setup_tasks(request.user)})


class TeamLeaderSetupView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def patch(self, request, team_id):
        team = get_object_or_404(StudentTeam.objects.select_for_update(), pk=team_id,
            leader=request.user, memberships__student=request.user, semester=get_active_semester())
        if not team.setup_pending:
            raise ValidationError('Team setup is already complete. Ask your team manager for later name changes.')
        name = serializers.CharField(max_length=120).run_validation(request.data.get('name'))
        if StudentTeam.objects.filter(name=name, level=team.level).exclude(pk=team.pk).exists():
            raise ValidationError({'name': 'Another team already uses this name. Choose a different name.'})
        previous = team.name
        team.name, team.setup_pending = name, False
        try:
            with transaction.atomic():
                team.save(update_fields=['name', 'setup_pending', 'updated_at'])
        except (IntegrityError, ModelValidationError) as exc:
            raise ValidationError({'name': 'This team name is no longer available. Choose another name.'}) from exc
        log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
            action='team.leader_setup', target=team, request=request, strict=True,
            old_values={'name': previous}, new_values={'name': team.name})
        return Response({'id': team.pk, 'name': team.name, 'teams': setup_tasks(request.user)})
