from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings

from .models import SystemAuditLog, SystemAuditReview, User
from .tokens import DefensysRefreshToken, REMEMBER_ME_CLAIM


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True)
    confirm_password = serializers.CharField(write_only=True)

    def validate_current_password(self, value):
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError('Current password is incorrect.')
        return value

    def validate(self, attrs):
        if attrs['new_password'] != attrs['confirm_password']:
            raise serializers.ValidationError(
                {'confirm_password': 'New password and confirmation do not match.'}
            )
        validate_password(attrs['new_password'], user=self.context['request'].user)
        return attrs


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
    team_id = serializers.SerializerMethodField()
    facultyRoles = serializers.SerializerMethodField()
    is_project_manager = serializers.SerializerMethodField()
    managed_section = serializers.SerializerMethodField()
    has_staff_workspace = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'phone_number', 'first_name', 'last_name', 'name', 'role',
            'team_id', 'is_panelist', 'is_pit_lead', 'pit_lead_year', 'is_adviser',
            'is_documenter', 'is_uploader', 'e_signature', 'avatar', 'facultyRoles',
            'is_project_manager', 'managed_section',
            'has_staff_workspace',
        ]

    def get_has_staff_workspace(self, obj):
        """Navigation hint, including instructors whose role comes from assignments."""
        if obj.role == 'admin':
            return True
        if obj.role != 'faculty':
            return False
        if obj.is_pit_lead or obj.is_adviser or obj.is_documenter or obj.is_uploader:
            return True
        from academic_period_management.services import active_semester
        from user_management.models import SectionInstructorAssignment
        assignments = SectionInstructorAssignment.objects.filter(faculty=obj, is_active=True)
        semester = active_semester()
        if semester:
            assignments = assignments.filter(semester=semester)
        return assignments.exists()

    def get_team_id(self, obj):
        membership = obj.team_memberships.first()
        return str(membership.team_id) if membership else None

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


class SystemAuditReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = SystemAuditReview
        fields = [
            'id', 'reviewer', 'reviewer_name', 'reviewer_role', 'reviewer_year',
            'from_status', 'to_status', 'reason', 'created_at',
        ]


class SystemAuditLogListSerializer(serializers.ListSerializer):
    def to_representation(self, data):
        from .audit_references import AuditReferenceResolver

        logs = list(data.all() if hasattr(data, 'all') else data)
        self.context['audit_reference_resolver'] = AuditReferenceResolver(logs)
        return super().to_representation(logs)


class SystemAuditLogSerializer(serializers.ModelSerializer):
    review_history = SystemAuditReviewSerializer(source='reviews', many=True, read_only=True)
    actor_name = serializers.SerializerMethodField()
    category_label = serializers.CharField(source='get_category_display', read_only=True)
    review_status_label = serializers.CharField(source='get_review_status_display', read_only=True)
    evidence = serializers.SerializerMethodField()

    class Meta:
        model = SystemAuditLog
        list_serializer_class = SystemAuditLogListSerializer
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
            'evidence',
            'reviewed_by',
            'reviewed_at',
            'reviewed_by_name',
            'reviewed_by_role',
            'reviewed_by_year',
            'review_history',
            'ip_address',
            'user_agent',
            'created_at',
        ]

    def to_representation(self, instance):
        from .audit_references import AuditReferenceResolver

        result = super().to_representation(instance)
        resolver = self.context.get('audit_reference_resolver') or AuditReferenceResolver([instance])
        result['target_label'] = resolver.target_label(instance)
        result['display_old_values'] = resolver.display_values(instance, 'old_values')
        result['display_new_values'] = resolver.display_values(instance, 'new_values')
        return result

    def get_evidence(self, obj):
        from .audit import audit_evidence
        return audit_evidence(obj)

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
        data['user'] = UserSerializer(self.user, context=self.context).data
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
