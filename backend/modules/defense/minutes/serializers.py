from rest_framework import serializers
from django.contrib.auth import get_user_model
from defense.scheduler.serializers import DefenseScheduleSerializer, display_name
from .models import DefenseMinutes, MinutesPanelistComment

User = get_user_model()

class DocumenterAssignmentSerializer(DefenseScheduleSerializer):
    class Meta(DefenseScheduleSerializer.Meta):
        pass


class MinutesPanelistCommentSerializer(serializers.ModelSerializer):
    class Meta:
        model = MinutesPanelistComment
        fields = [
            'id',
            'panelist',
            'panelist_name_snapshot',
            'panelist_role_snapshot',
            'comments',
            'display_order',
        ]
        read_only_fields = ['id', 'panelist', 'panelist_name_snapshot', 'panelist_role_snapshot', 'display_order']


class DefenseMinutesSerializer(serializers.ModelSerializer):
    schedule = serializers.SerializerMethodField()
    panelist_comments = MinutesPanelistCommentSerializer(many=True, read_only=True)
    documenter_signed_by_name = serializers.SerializerMethodField()
    adviser_signed_by_name = serializers.SerializerMethodField()
    chairman_signed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = DefenseMinutes
        fields = [
            'id',
            'schedule',
            'team_name',
            'project_title',
            'adviser_name',
            'defense_stage_label',
            'defense_date',
            'defense_time',
            'room',
            'documenter_name',
            'status',
            'documenter_signed_at',
            'documenter_signed_by',
            'documenter_signed_by_name',
            'adviser_signed_at',
            'adviser_signed_by',
            'adviser_signed_by_name',
            'chairman_signed_at',
            'chairman_signed_by',
            'chairman_signed_by_name',
            'pdf_file',
            'panelist_comments',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id', 'schedule', 'team_name', 'project_title', 'adviser_name',
            'defense_stage_label', 'defense_date', 'defense_time', 'room',
            'documenter_name', 'status', 'documenter_signed_at', 'documenter_signed_by',
            'adviser_signed_at', 'adviser_signed_by', 'chairman_signed_at', 'chairman_signed_by',
            'pdf_file', 'created_at', 'updated_at'
        ]

    def get_documenter_signed_by_name(self, obj):
        return display_name(obj.documenter_signed_by)

    def get_adviser_signed_by_name(self, obj):
        return display_name(obj.adviser_signed_by)

    def get_chairman_signed_by_name(self, obj):
        return display_name(obj.chairman_signed_by)

    def get_schedule(self, obj):
        schedule = obj.schedule
        return {
            'id': schedule.id,
            'documenter': schedule.documenter_id,
            'team_adviser_id': schedule.team.adviser_id if (schedule.team and schedule.team.adviser) else None,
            'status': schedule.status,
        }

