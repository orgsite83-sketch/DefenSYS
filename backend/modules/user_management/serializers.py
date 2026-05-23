from django.contrib.auth import get_user_model
from rest_framework import serializers

from defense.scheduler.models import DefenseSchedule
from .models import FacultyRoleAssignment, GuestPanelistCode
from .role_assignments import (
    ROLE_LABELS,
    compute_display_role,
    ensure_active_role_history,
    record_role_changes,
    snapshot_role_flags,
)


User = get_user_model()


def schedule_label(schedule):
    team_name = getattr(schedule.team, 'name', 'Team')
    stage_label = schedule.stage_label or schedule.get_scope_display()
    date = schedule.scheduled_date.isoformat() if schedule.scheduled_date else ''
    time = schedule.start_time.strftime('%I:%M %p').lstrip('0') if schedule.start_time else ''
    room = f' - {schedule.room}' if schedule.room else ''
    return f'{team_name} - {stage_label} - {date} {time}{room}'.strip()


class FacultyRoleAssignmentSerializer(serializers.ModelSerializer):
    role_label = serializers.SerializerMethodField()
    semester = serializers.SerializerMethodField()
    changed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = FacultyRoleAssignment
        fields = [
            'id',
            'role_key',
            'role_label',
            'role_detail',
            'semester',
            'year_level',
            'action',
            'changed_at',
            'changed_by_name',
        ]

    def get_role_label(self, obj):
        return ROLE_LABELS.get(obj.role_key, obj.role_key)

    def get_semester(self, obj):
        if obj.semester_id is None:
            return None
        return obj.semester.display_name

    def get_changed_by_name(self, obj):
        if obj.changed_by_id is None:
            return None
        full_name = f'{obj.changed_by.first_name} {obj.changed_by.last_name}'.strip()
        return full_name or obj.changed_by.username


class ManagedUserSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    facultyRoles = serializers.SerializerMethodField()
    displayRole = serializers.SerializerMethodField()
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'email',
            'first_name',
            'last_name',
            'name',
            'role',
            'team_id',
            'is_active',
            'is_panelist',
            'is_pit_lead',
            'pit_lead_year',
            'is_adviser',
            'is_repo_assistant',
            'is_uploader',
            'facultyRoles',
            'displayRole',
            'password',
        ]
        extra_kwargs = {
            'username': {'required': True},
            'email': {'required': False, 'allow_blank': True},
            'first_name': {'required': False, 'allow_blank': True},
            'last_name': {'required': False, 'allow_blank': True},
            'team_id': {'required': False, 'allow_null': True, 'allow_blank': True},
            'pit_lead_year': {'required': False, 'allow_null': True, 'allow_blank': True},
        }

    def get_name(self, obj):
        full_name = f'{obj.first_name} {obj.last_name}'.strip()
        return full_name or obj.username

    def get_facultyRoles(self, obj):
        return {
            'panelist': obj.is_panelist,
            'pitLead': obj.is_pit_lead,
            'pitLeadYear': obj.pit_lead_year,
            'adviser': obj.is_adviser,
            'repoAssistant': obj.is_repo_assistant,
            'uploader': obj.is_uploader,
        }

    def get_displayRole(self, obj):
        return compute_display_role(obj)

    def validate_username(self, value):
        queryset = User.objects.filter(username=value)
        if self.instance is not None:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError('A user with this ID number already exists.')
        return value

    def validate(self, attrs):
        role = attrs.get('role', getattr(self.instance, 'role', 'student'))
        if role not in dict(User.ROLE_CHOICES):
            raise serializers.ValidationError({'role': 'Invalid user role.'})
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password', '') or validated_data['username']
        self._normalize_role_fields(validated_data)
        user = User.objects.create_user(password=password, **validated_data)
        user.adviser_phase = None
        user.save(update_fields=['adviser_phase'])
        return user

    def update(self, instance, validated_data):
        password = validated_data.pop('password', '')
        before_flags = snapshot_role_flags(instance)
        self._normalize_role_fields(validated_data, instance=instance)

        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.adviser_phase = None
        if password:
            instance.set_password(password)
        instance.save()

        request = self.context.get('request')
        changed_by = getattr(request, 'user', None) if request else None
        record_role_changes(instance, before_flags, changed_by=changed_by)
        ensure_active_role_history(instance, changed_by=changed_by)
        return instance

    def _normalize_role_fields(self, attrs, instance=None):
        role = attrs.get('role', getattr(instance, 'role', None))
        is_faculty = role in ['admin', 'faculty']

        if not is_faculty:
            attrs['is_panelist'] = False
            attrs['is_pit_lead'] = False
            attrs['pit_lead_year'] = None
            attrs['is_adviser'] = False
            attrs['is_repo_assistant'] = False
            attrs['is_uploader'] = False

        if not attrs.get('is_pit_lead', getattr(instance, 'is_pit_lead', False)):
            attrs['pit_lead_year'] = None
            attrs['is_repo_assistant'] = False


class BulkUserRowSerializer(serializers.Serializer):
    id_number = serializers.CharField(max_length=150)
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True)
    role = serializers.ChoiceField(choices=[choice[0] for choice in User.ROLE_CHOICES], default='student')
    year_level = serializers.CharField(required=False, allow_blank=True, max_length=20)


class DefenseScheduleOptionSerializer(serializers.ModelSerializer):
    label = serializers.SerializerMethodField()
    team_name = serializers.CharField(source='team.name', read_only=True)
    project_title = serializers.CharField(source='team.project_title', read_only=True)
    stage_label = serializers.CharField(read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)

    class Meta:
        model = DefenseSchedule
        fields = [
            'id',
            'label',
            'scope',
            'team_name',
            'project_title',
            'stage_label',
            'display_semester',
            'scheduled_date',
            'start_time',
            'room',
            'status',
        ]

    def get_label(self, obj):
        return schedule_label(obj)


class GuestPanelistCodeSerializer(serializers.ModelSerializer):
    defense_schedule_label = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()

    class Meta:
        model = GuestPanelistCode
        fields = [
            'id',
            'code',
            'guest_name',
            'email',
            'defense_schedule',
            'defense_schedule_label',
            'is_active',
            'status',
            'expires_at',
            'used_at',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'code',
            'defense_schedule_label',
            'status',
            'created_at',
            'updated_at',
        ]

    def get_defense_schedule_label(self, obj):
        return schedule_label(obj.defense_schedule)

    def get_status(self, obj):
        return 'Active' if obj.is_active else 'Revoked'


class GuestPanelistCodeCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = GuestPanelistCode
        fields = ['guest_name', 'email', 'defense_schedule', 'expires_at']
        extra_kwargs = {
            'email': {'required': False, 'allow_blank': True},
            'expires_at': {'required': False, 'allow_null': True},
        }

    def validate_guest_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError('Guest panelist name is required.')
        return value

    def validate_defense_schedule(self, value):
        if value.status in [DefenseSchedule.STATUS_CANCELLED, DefenseSchedule.STATUS_ARCHIVED]:
            raise serializers.ValidationError('Guest codes can only be assigned to active defense schedules.')
        return value
