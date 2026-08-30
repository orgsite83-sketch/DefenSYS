from django.contrib.auth import get_user_model
from rest_framework import serializers

from defense.scheduler.models import DefenseSchedule
from .models import FacultyRoleAssignment, GuestPanelistCode, SectionInstructorAssignment
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


def user_display_name(user):
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


class SectionInstructorAssignmentSerializer(serializers.ModelSerializer):
    faculty_name = serializers.SerializerMethodField()
    faculty_username = serializers.CharField(source='faculty.username', read_only=True)
    assigned_by_name = serializers.SerializerMethodField()
    semester_label = serializers.CharField(source='semester.display_name', read_only=True)

    class Meta:
        model = SectionInstructorAssignment
        fields = [
            'id',
            'faculty',
            'faculty_username',
            'faculty_name',
            'semester',
            'semester_label',
            'year_level',
            'section',
            'assigned_by',
            'assigned_by_name',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['assigned_by']

    def get_faculty_name(self, obj):
        return user_display_name(obj.faculty)

    def get_assigned_by_name(self, obj):
        return user_display_name(obj.assigned_by) if obj.assigned_by_id else None


class ManagedUserSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    team_id = serializers.SerializerMethodField()
    facultyRoles = serializers.SerializerMethodField()
    displayRole = serializers.SerializerMethodField()
    instructor_assignments = serializers.SerializerMethodField()
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'email',
            'phone_number',
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
            'is_documenter',
            'is_uploader',
            'e_signature',
            'facultyRoles',
            'displayRole',
            'instructor_assignments',
            'password',
        ]
        extra_kwargs = {
            'username': {'required': True},
            'email': {'required': False, 'allow_blank': True},
            'phone_number': {'required': False, 'allow_blank': True},
            'first_name': {'required': False, 'allow_blank': True},
            'last_name': {'required': False, 'allow_blank': True},
            'pit_lead_year': {'required': False, 'allow_null': True, 'allow_blank': True},
        }

    def get_team_id(self, obj):
        membership = obj.team_memberships.first()
        return str(membership.team_id) if membership else None

    def get_name(self, obj):
        full_name = f'{obj.first_name} {obj.last_name}'.strip()
        return full_name or obj.username

    def get_facultyRoles(self, obj):
        from user_management.models import SectionInstructorAssignment
        is_pit_instructor = SectionInstructorAssignment.objects.filter(
            faculty=obj, is_active=True
        ).exists()
        return {
            'panelist': obj.is_panelist,
            'pitLead': obj.is_pit_lead,
            'pitLeadYear': obj.pit_lead_year,
            'pitInstructor': is_pit_instructor,
            'adviser': obj.is_adviser,
            'documenter': obj.is_documenter,
            'uploader': obj.is_uploader,
        }

    def get_displayRole(self, obj):
        return compute_display_role(obj)

    def get_instructor_assignments(self, obj):
        from user_management.models import SectionInstructorAssignment
        from academic_period_management.services import active_semester
        sem = active_semester()
        qs = SectionInstructorAssignment.objects.filter(faculty=obj, is_active=True)
        if sem:
            qs = qs.filter(semester=sem)
        return [
            {
                'id': a.id,
                'year_level': a.year_level,
                'section': a.section,
                'semester': a.semester.display_name,
            }
            for a in qs
        ]

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
        is_pit_lead = attrs.get('is_pit_lead', getattr(self.instance, 'is_pit_lead', False))
        if role in ['admin', 'faculty'] and is_pit_lead:
            pit_year = (attrs.get('pit_lead_year', getattr(self.instance, 'pit_lead_year', None)) or '').strip()
            if not pit_year:
                raise serializers.ValidationError(
                    {'pit_lead_year': 'A PIT Lead year level (1st, 2nd, or 3rd Year) is required when assigning a user as PIT Lead.'}
                )
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password', '') or validated_data['username']
        self._normalize_role_fields(validated_data)
        user = User.objects.create_user(password=password, **validated_data)
        return user

    def update(self, instance, validated_data):
        password = validated_data.pop('password', '')
        before_flags = snapshot_role_flags(instance)
        self._normalize_role_fields(validated_data, instance=instance)

        for field, value in validated_data.items():
            setattr(instance, field, value)

        request = self.context.get('request')
        changed_by = getattr(request, 'user', None) if request else None

        if password:
            instance.set_password(password)
            try:
                from notifications.email_service import send_admin_password_reset_email
                send_admin_password_reset_email(instance)
            except Exception:
                pass
            try:
                from notifications.services import create_notification
                from notifications.models import NotificationCategory, NotificationPriority
                create_notification(
                    recipient=instance,
                    sender=changed_by,
                    title='Password Reset by Administrator',
                    message='An administrator has reset your account password. Please sign in with your updated credentials.',
                    category=NotificationCategory.SECURITY,
                    priority=NotificationPriority.URGENT,
                    action_route='/me/profile',
                )
            except Exception:
                pass

        instance.save()

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
            attrs['is_documenter'] = False
            attrs['is_uploader'] = False

        if not attrs.get('is_pit_lead', getattr(instance, 'is_pit_lead', False)):
            attrs['pit_lead_year'] = None


import re


def parse_faculty_roles_dict(raw_str):
    """
    Parse a raw role string (e.g. 'Panelist, Adviser', 'PIT Lead 1st Year / Panelist', 'Admin')
    into a dict of base role and capability flags.
    """
    input_str = (raw_str or '').strip()
    if not input_str:
        return {
            'role': 'faculty',
            'is_panelist': False,
            'is_adviser': False,
            'is_pit_lead': False,
            'pit_lead_year': None,
            'is_documenter': False,
            'is_uploader': False,
        }

    lower = input_str.lower()
    if 'admin' in lower:
        return {
            'role': 'admin',
            'is_panelist': False,
            'is_adviser': False,
            'is_pit_lead': False,
            'pit_lead_year': None,
            'is_documenter': False,
            'is_uploader': False,
        }

    if lower in ('student', 'std'):
        return {
            'role': 'student',
            'is_panelist': False,
            'is_adviser': False,
            'is_pit_lead': False,
            'pit_lead_year': None,
            'is_documenter': False,
            'is_uploader': False,
        }

    tokens = [t.strip().lower() for t in re.split(r'[,/|;&+\n]', input_str) if t.strip()]

    is_panelist = False
    is_adviser = False
    is_pit_lead = False
    pit_lead_year = None
    is_documenter = False
    is_uploader = False

    def _extract_year(text):
        c = text.lower()
        if '1st' in c or 'first' in c or 'year 1' in c or 'yr 1' in c or ' 1' in c:
            return '1st Year'
        if '2nd' in c or 'second' in c or 'year 2' in c or 'yr 2' in c or ' 2' in c:
            return '2nd Year'
        if '3rd' in c or 'third' in c or 'year 3' in c or 'yr 3' in c or ' 3' in c:
            return '3rd Year'
        if '4th' in c or 'fourth' in c or 'year 4' in c or 'yr 4' in c or ' 4' in c:
            return '4th Year'
        return None

    for token in (tokens if tokens else [lower]):
        if 'panel' in token:
            is_panelist = True
        if 'advis' in token:
            is_adviser = True
        if 'lead' in token or 'pit' in token:
            is_pit_lead = True
            y = _extract_year(token)
            if y:
                pit_lead_year = y
        if 'doc' in token or 'documenter' in token:
            is_documenter = True
        if 'upload' in token:
            is_uploader = True

    if 'panel' in lower:
        is_panelist = True
    if 'advis' in lower:
        is_adviser = True
    if 'pit' in lower or 'lead' in lower:
        is_pit_lead = True
        if not pit_lead_year:
            pit_lead_year = _extract_year(lower)
    if 'documenter' in lower:
        is_documenter = True
    if 'uploader' in lower:
        is_uploader = True

    return {
        'role': 'faculty',
        'is_panelist': is_panelist,
        'is_adviser': is_adviser,
        'is_pit_lead': is_pit_lead,
        'pit_lead_year': pit_lead_year if is_pit_lead else ('1st Year' if is_pit_lead else None),
        'is_documenter': is_documenter,
        'is_uploader': is_uploader,
    }


class BulkUserRowSerializer(serializers.Serializer):
    id_number = serializers.CharField(required=False, allow_blank=True, max_length=150)
    username = serializers.CharField(required=False, allow_blank=True, max_length=150)
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True)
    phone_number = serializers.CharField(required=False, allow_blank=True, max_length=32)
    contact = serializers.CharField(required=False, allow_blank=True, max_length=32)
    role = serializers.CharField(required=False, allow_blank=True, default='student')
    raw_role = serializers.CharField(required=False, allow_blank=True, max_length=255)
    is_panelist = serializers.BooleanField(required=False)
    is_adviser = serializers.BooleanField(required=False)
    is_pit_lead = serializers.BooleanField(required=False)
    pit_lead_year = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=50)
    is_documenter = serializers.BooleanField(required=False)
    is_uploader = serializers.BooleanField(required=False)
    year_level = serializers.CharField(required=False, allow_blank=True, max_length=20)
    section = serializers.CharField(required=False, allow_blank=True, max_length=80)
    instructor = serializers.CharField(required=False, allow_blank=True, max_length=150)
    instructor_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    faculty = serializers.CharField(required=False, allow_blank=True, max_length=150)

    def validate(self, attrs):
        id_num = (attrs.get('id_number') or attrs.get('username') or '').strip()
        if not id_num:
            raise serializers.ValidationError({'id_number': 'ID number or username is required.'})
        attrs['id_number'] = id_num

        phone = (attrs.get('phone_number') or attrs.get('contact') or '').strip()
        if phone:
            attrs['phone_number'] = phone

        raw_role_str = (attrs.get('raw_role') or attrs.get('role') or '').strip()
        parsed_role = parse_faculty_roles_dict(raw_role_str)

        input_role = (attrs.get('role') or '').strip().lower()
        if input_role in [choice[0] for choice in User.ROLE_CHOICES]:
            base_role = input_role
        else:
            base_role = parsed_role['role']
        attrs['role'] = base_role

        if 'is_panelist' not in attrs:
            attrs['is_panelist'] = parsed_role['is_panelist']
        if 'is_adviser' not in attrs:
            attrs['is_adviser'] = parsed_role['is_adviser']
        if 'is_pit_lead' not in attrs:
            attrs['is_pit_lead'] = parsed_role['is_pit_lead']
        if 'pit_lead_year' not in attrs:
            attrs['pit_lead_year'] = parsed_role['pit_lead_year']
        if 'is_documenter' not in attrs:
            attrs['is_documenter'] = parsed_role['is_documenter']
        if 'is_uploader' not in attrs:
            attrs['is_uploader'] = parsed_role['is_uploader']

        return attrs

    def validate_year_level(self, value):
        if not value:
            return value
        valid_choices = ['1st Year', '2nd Year', '3rd Year', '4th Year']
        if value not in valid_choices:
            raise serializers.ValidationError(
                f"'{value}' is not a valid year level. Must be one of: {', '.join(valid_choices)}."
            )
        return value


class OfficialClassListStudentSerializer(serializers.Serializer):
    id_number = serializers.CharField(max_length=150)
    full_name = serializers.CharField(required=False, allow_blank=True, max_length=255)
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True)
    phone_number = serializers.CharField(required=False, allow_blank=True, max_length=32)
    contact = serializers.CharField(required=False, allow_blank=True, max_length=32)
    program = serializers.CharField(required=False, allow_blank=True, max_length=80)
    year_level = serializers.CharField(required=False, allow_blank=True, max_length=20)
    section = serializers.CharField(required=False, allow_blank=True, max_length=80)
    instructor = serializers.CharField(required=False, allow_blank=True, max_length=150)
    instructor_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    faculty = serializers.CharField(required=False, allow_blank=True, max_length=150)

    def validate(self, attrs):
        if not attrs.get('full_name') and not (attrs.get('first_name') or attrs.get('last_name')):
            raise serializers.ValidationError({
                'full_name': 'Full name or first/last name is required.',
            })
        phone = (attrs.get('phone_number') or attrs.get('contact') or '').strip()
        if phone:
            attrs['phone_number'] = phone
        return attrs


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
