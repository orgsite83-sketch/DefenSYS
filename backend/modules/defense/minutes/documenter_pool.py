"""Admin-managed eligibility, backed by the existing documenter role flag."""
from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from user_management.permissions import IsSystemAdmin
from user_management.role_assignments import record_role_changes, snapshot_role_flags
from defense.scheduler.models import DefenseSchedule
from .models import DefenseMinutes


def pending_assignments(user_ids):
    return DefenseSchedule.objects.filter(documenter_id__in=user_ids).exclude(
        status=DefenseSchedule.STATUS_CANCELLED,
    ).filter(Q(minutes__isnull=True) | ~Q(minutes__status=DefenseMinutes.STATUS_COMPLETED))


def pool_payload():
    User = get_user_model()
    people = list(User.objects.filter(role__in=('faculty', 'admin'), is_active=True)
                  .order_by('last_name', 'first_name', 'username'))
    assignments = {}
    for schedule in pending_assignments([user.pk for user in people]).select_related('team'):
        assignments.setdefault(schedule.documenter_id, []).append({
            'id': schedule.pk, 'team_name': schedule.team.name,
            'scheduled_date': schedule.scheduled_date.isoformat(),
        })
    return {'people': [{
        'id': user.pk, 'name': user.get_full_name() or user.username,
        'role': user.role, 'is_documenter': user.is_documenter,
        'pending_assignments': assignments.get(user.pk, []),
    } for user in people]}


class PoolChangeSerializer(serializers.Serializer):
    id = serializers.IntegerField(min_value=1)
    is_documenter = serializers.BooleanField()


class PoolUpdateSerializer(serializers.Serializer):
    changes = PoolChangeSerializer(many=True, allow_empty=False)

    def validate_changes(self, changes):
        if len({change['id'] for change in changes}) != len(changes):
            raise serializers.ValidationError('Each person may appear only once.')
        return changes


class DocumenterPoolView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        return Response(pool_payload())

    def patch(self, request):
        serializer = PoolUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        changes = serializer.validated_data['changes']
        User = get_user_model()
        with transaction.atomic():
            people = {user.pk: user for user in User.objects.select_for_update().filter(
                pk__in=[change['id'] for change in changes], is_active=True,
                role__in=('faculty', 'admin'),
            )}
            if len(people) != len(changes):
                raise serializers.ValidationError({'detail': 'Choose active faculty or administrators.'})
            removing = [change['id'] for change in changes if not change['is_documenter']]
            if pending_assignments(removing).exists():
                raise serializers.ValidationError({
                    'detail': 'Reassign or finalize outstanding minutes before removing a documenter from the pool.',
                })
            for change in changes:
                user = people[change['id']]
                before = snapshot_role_flags(user)
                user.is_documenter = change['is_documenter']
                user.save(update_fields=['is_documenter'])
                record_role_changes(user, before, changed_by=request.user)
        return Response(pool_payload())
