"""Reviewed name-only repairs. Never run automatically during an import."""
from django.contrib.auth import get_user_model
from django.core import signing
from django.db import transaction
from rest_framework import serializers
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defensys_backend.name_validation import NameQualityMixin
from defensys_backend.person_names import name_encoding_issue
from .permissions import IsSystemAdmin

SALT = 'user-management.name-repair.v1'


class NameRepairInput(NameQualityMixin, serializers.Serializer):
    username = serializers.CharField(max_length=150)
    expected_role = serializers.ChoiceField(choices=['student', 'faculty', 'admin'])
    first_name = serializers.CharField(max_length=150, allow_blank=True)
    last_name = serializers.CharField(max_length=150, allow_blank=True)
    source_filename = serializers.CharField(max_length=255)

    def to_internal_value(self, data):
        if set(data) - set(self.fields):
            raise ValidationError({'detail': 'Submit only the account ID, role, source and reviewed name fields.'})
        return super().to_internal_value(data)

    def validate(self, data):
        if not (data['first_name'] or data['last_name']):
            raise ValidationError('Enter the verified official name.')
        return data


class NameRepairPreviewView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        serializer = NameRepairInput(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = get_user_model().objects.filter(username=data['username']).first()
        if not user or user.role != data['expected_role']:
            raise ValidationError('The registered account ID and role must match the selected account.')
        before = {'first_name': user.first_name, 'last_name': user.last_name}
        after = {field: data[field] for field in before}
        if before == after:
            raise ValidationError('The verified name is unchanged.')
        # Only identity fields are captured; imported capability/contact defaults
        # never reach the repair apply path.
        state = {'actor': request.user.pk, 'pk': user.pk, 'username': user.username,
                 'role': user.role, 'before': before, 'after': after,
                 'source_filename': data['source_filename']}
        return Response({**{key: state[key] for key in ('username', 'role', 'before', 'after', 'source_filename')},
                         'preview_token': signing.dumps(state, salt=SALT, compress=True)})


class NameRepairApplyView(APIView):
    permission_classes = [IsSystemAdmin]

    @transaction.atomic
    def post(self, request):
        if set(request.data) != {'preview_token'}:
            raise ValidationError('Apply the reviewed name repair using its preview token only.')
        try:
            state = signing.loads(request.data['preview_token'], salt=SALT, max_age=900)
        except (signing.BadSignature, TypeError, ValueError):
            raise ValidationError('This name review expired or is invalid. Review the repair again.')
        if state['actor'] != request.user.pk:
            raise ValidationError('This name review belongs to another administrator.')
        user = get_user_model().objects.select_for_update().filter(pk=state['pk']).first()
        if (not user or user.username != state['username'] or user.role != state['role']
                or any(getattr(user, key) != value for key, value in state['before'].items())):
            return Response({'detail': 'The account changed. Review the name repair again.'}, status=409)
        if any(name_encoding_issue(value) for value in state['after'].values()):
            raise ValidationError('The reviewed name contains damaged characters.')
        for field, value in state['after'].items():
            setattr(user, field, value)
        user.save(update_fields=['first_name', 'last_name'])
        log_high_impact_action(category=SystemAuditLog.CATEGORY_USER_MANAGEMENT,
            action='user.name_repair', target=user, request=request, strict=True,
            old_values={'username': user.username, **state['before']},
            new_values={'username': user.username, **state['after'], 'source_filename': state['source_filename']},
            reason=f"Reviewed official name repair from {state['source_filename']}")
        return Response({'username': user.username, **state['after'], 'detail': 'Account name repaired.'})
