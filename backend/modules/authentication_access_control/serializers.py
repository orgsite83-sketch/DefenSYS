from rest_framework import serializers
from .models import User
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer


class UserSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    facultyRoles = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name', 'name', 'role',
            'team_id', 'is_panelist', 'is_pit_lead', 'pit_lead_year', 'is_adviser',
            'adviser_phase', 'is_repo_assistant', 'is_uploader', 'facultyRoles',
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
            'adviserPhase': obj.adviser_phase,
            'repoAssistant': obj.is_repo_assistant,
            'uploader': obj.is_uploader,
        }


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        data = super().validate(attrs)
        
        # Add extra responses here
        data['user'] = UserSerializer(self.user).data
        return data
