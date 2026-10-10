from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.exceptions import PermissionDenied
from authentication_access_control.scopes import is_admin_user

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule
from .models import ExternalEvaluator, GuestPanelistCode
from .permissions import IsPitLeadOrAdmin, IsSystemAdmin
from .external_evaluators import (
    create_invitations, evaluator_payload, invitation_payload, management_payload,
    register_evaluator, resolve_evaluators, update_evaluator, update_invitation,
)


class EvaluatorCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True, default='')


class EvaluatorReviewSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=150, required=False)
    email = serializers.EmailField(required=False, allow_blank=True)
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True)
    status = serializers.ChoiceField(choices=['approved', 'declined'], required=False)
    is_active = serializers.BooleanField(required=False)
    review_note = serializers.CharField(max_length=1000, required=False, allow_blank=True)


class InvitationCreateSerializer(serializers.Serializer):
    evaluator_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=30)
    schedule_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=500)
    expires_at = serializers.DateTimeField(required=False)


class InvitationUpdateSerializer(serializers.Serializer):
    is_active = serializers.BooleanField()
    expires_at = serializers.DateTimeField(required=False)


def audit(request, action, item, values, old_values=None):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_GUEST_ACCESS,
        action=action, target=item, new_values=values, old_values=old_values or {},
        reason=getattr(item, 'review_note', '') or action.replace('_', ' ').replace('.', ': '), request=request)


class ExternalEvaluatorsView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def get(self, request):
        return Response(management_payload(request.user))

    def post(self, request):
        serializer = EvaluatorCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        item, created = register_evaluator(request.user, serializer.validated_data)
        if created:
            audit(request, 'external_evaluator.create', item, {'status': item.status})
        return Response({**management_payload(request.user), 'evaluator': evaluator_payload(item)},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


class ExternalEvaluatorDetailView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def get(self, request, evaluator_id):
        items = ExternalEvaluator.objects.select_related('created_by', 'reviewed_by')
        if not is_admin_user(request.user):
            items = items.filter(created_by=request.user)
        item = get_object_or_404(items, pk=evaluator_id)
        return Response({'request': evaluator_payload(item), 'can_review': is_admin_user(request.user)})

    def patch(self, request, evaluator_id):
        if not is_admin_user(request.user):
            raise PermissionDenied('Only admins can approve or update external evaluators.')
        serializer = EvaluatorReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        item = get_object_or_404(ExternalEvaluator, pk=evaluator_id)
        old = {'name': item.name, 'email': item.email, 'institution': item.institution, 'status': item.status, 'is_active': item.is_active}
        item = update_evaluator(request.user, item, serializer.validated_data)
        audit(request, 'external_evaluator.review', item, {'name': item.name, 'email': item.email, 'institution': item.institution, 'status': item.status, 'is_active': item.is_active}, old)
        return Response(management_payload(request.user))


class ExternalInvitationsView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def post(self, request):
        serializer = InvitationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        ids = set(data['schedule_ids'])
        schedules = list(DefenseSchedule.objects.filter(pk__in=ids).select_related('team', 'semester', 'defense_stage').order_by('scheduled_date', 'start_time', 'pk'))
        if len(schedules) != len(ids):
            raise serializers.ValidationError({'schedule_ids': 'A selected defense no longer exists.'})
        invitations = create_invitations(resolve_evaluators(data['evaluator_ids'], request.user), schedules, request.user, data.get('expires_at'))
        return Response({**management_payload(request.user), 'created_invitations': [invitation_payload(i) for i in invitations]}, status=201)


class ExternalInvitationDetailView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def patch(self, request, invitation_id):
        serializer = InvitationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        item = update_invitation(request.user, get_object_or_404(GuestPanelistCode, pk=invitation_id), serializer.validated_data)
        audit(request, 'external_invitation.renew' if item.is_active else 'external_invitation.revoke', item,
            {'is_active': item.is_active, 'expires_at': item.expires_at.isoformat() if item.expires_at else None})
        return Response({**management_payload(request.user), 'created_invitations': [invitation_payload(item)] if item.is_active else []})
