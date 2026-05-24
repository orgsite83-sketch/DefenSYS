from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings

from .models import User
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

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 'name', 'role',
            'team_id', 'is_panelist', 'is_pit_lead', 'pit_lead_year', 'is_adviser',
            'is_repo_assistant', 'repo_assistant_year', 'is_uploader', 'facultyRoles',
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
            'repoAssistant': obj.is_repo_assistant,
            'repoAssistantYear': getattr(obj, 'repo_assistant_year', '') or '',
            'uploader': obj.is_uploader,
        }


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
