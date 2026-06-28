from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings

from .models import SystemAuditLog, User
from .tokens import DefensysRefreshToken, REMEMBER_ME_CLAIM


def _coerce_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip().lower() in ('1', 'true', 'yes', 'on')
    return bool(value)


class UserSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    facultyRoles = serializers.SerializerMethodField()
    is_project_manager = serializers.SerializerMethodField()
    managed_section = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 'name', 'role',
            'team_id', 'is_panelist', 'is_pit_lead', 'pit_lead_year', 'is_adviser',
            'is_documenter', 'is_uploader', 'e_signature', 'facultyRoles',
            'is_project_manager', 'managed_section',
        ]

    def get_name(self, obj):
        full_name = f"{obj.first_name} {obj.last_name}".strip()
        return full_name or obj.username

    def get_facultyRoles(self, obj):
        return {
            'panelist': obj.is_panelist,
            'pitLead': obj.is_pit_lead,
            'pitLeadYear': obj.pit_lead_year,
            'adviser': obj.is_adviser,
            'documenter': obj.is_documenter,
            'uploader': obj.is_uploader,
        }

    def get_is_project_manager(self, obj):
        if obj.role != 'student':
            return False
        from student_teams.models import SectionAssignment
        return SectionAssignment.objects.filter(
            project_manager=obj,
            semester__is_active=True
        ).exists()

    def get_managed_section(self, obj):
        if obj.role != 'student':
            return None
        from student_teams.models import SectionAssignment
        assignment = SectionAssignment.objects.filter(
            project_manager=obj,
            semester__is_active=True
        ).first()
        return assignment.section if assignment else None


class SystemAuditLogSerializer(serializers.ModelSerializer):
    actor_name = serializers.SerializerMethodField()
    category_label = serializers.CharField(source='get_category_display', read_only=True)
    review_status_label = serializers.CharField(source='get_review_status_display', read_only=True)

    class Meta:
        model = SystemAuditLog
        fields = [
            'id',
            'actor',
            'actor_name',
            'action',
            'category',
            'category_label',
            'target_type',
            'target_id',
            'old_values',
            'new_values',
            'reason',
            'review_status',
            'review_status_label',
            'ip_address',
            'user_agent',
            'created_at',
        ]

    def get_actor_name(self, obj):
        if obj.actor is None:
            return 'System'
        full_name = f'{obj.actor.first_name} {obj.actor.last_name}'.strip()
        return full_name or obj.actor.username


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    remember_me = serializers.BooleanField(required=False, default=False)

    def validate(self, attrs):
        remember_me = _coerce_bool(attrs.pop('remember_me', False))
        data = super().validate(attrs)

        refresh = DefensysRefreshToken.for_user(self.user, remember_me=remember_me)
        data['refresh'] = str(refresh)
        data['access'] = str(refresh.access_token)
        data['user'] = UserSerializer(self.user).data
        return data


class CustomTokenRefreshSerializer(TokenRefreshSerializer):
    token_class = DefensysRefreshToken

    def validate(self, attrs):
        refresh = self.token_class(attrs['refresh'])
        refresh.check_blacklist()

        user_id = refresh[api_settings.USER_ID_CLAIM]
        user = get_user_model().objects.get(**{api_settings.USER_ID_FIELD: user_id})
        remember_me = bool(refresh.get(REMEMBER_ME_CLAIM))

        new_refresh = DefensysRefreshToken.for_user(user, remember_me=remember_me)
        if settings.SIMPLE_JWT.get('ROTATE_REFRESH_TOKENS', False):
            try:
                refresh.blacklist()
            except AttributeError:
                pass

        return {
            'access': str(new_refresh.access_token),
            'refresh': str(new_refresh),
        }
