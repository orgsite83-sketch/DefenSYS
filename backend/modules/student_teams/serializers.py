from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import serializers

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from user_management.academic_records.models import StudentAcademicRecord
from user_management.academic_records.serializers import StudentOptionSerializer
from .adviser_assignments import record_team_adviser_change
from .team_levels import (
    infer_year_level_from_members,
    level_year as team_level_year,
    resolve_team_level,
    user_is_admin,
    user_is_pit_lead_only,
)
from defense.scheduler.models import DefenseSchedule

from .models import StudentTeam, TeamAdviserAssignment, TeamMembership
from .term_scope import (
    assert_active_semester_for_create,
    assert_team_writable,
    team_is_editable,
    term_status_for_team,
)


User = get_user_model()


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


def level_year(level):
    if level.startswith('1st Year'):
        return '1st Year'
    if level.startswith('2nd Year'):
        return '2nd Year'
    if level.startswith('3rd Year'):
        return '3rd Year'
    if level.startswith('4th Year'):
        return '4th Year'
    return ''


class AdviserOptionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'name', 'email']

    def get_name(self, obj):
        return display_name(obj)


class TeamMemberSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(source='student.id', read_only=True)
    username = serializers.CharField(source='student.username', read_only=True)
    name = serializers.SerializerMethodField()
    email = serializers.EmailField(source='student.email', read_only=True)

    class Meta:
        model = TeamMembership
        fields = ['id', 'username', 'name', 'email', 'is_leader', 'order']

    def get_name(self, obj):
        return display_name(obj.student)


class StudentTeamSerializer(serializers.ModelSerializer):
    leader_id = serializers.IntegerField(source='leader.id', read_only=True)
    leader_username = serializers.CharField(source='leader.username', read_only=True)
    leader_name = serializers.SerializerMethodField()
    adviser_id = serializers.IntegerField(source='adviser.id', read_only=True, allow_null=True)
    adviser_username = serializers.CharField(source='adviser.username', read_only=True, allow_null=True)
    adviser_name = serializers.SerializerMethodField()
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    semester = serializers.CharField(source='semester.label', read_only=True)
    school_year = serializers.CharField(source='semester.school_year.label', read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)
    member_ids = serializers.SerializerMethodField()
    members = TeamMemberSerializer(source='memberships', many=True, read_only=True)
    member_count = serializers.SerializerMethodField()
    is_capstone = serializers.BooleanField(read_only=True)
    deliverable_count = serializers.SerializerMethodField()
    defense_context = serializers.SerializerMethodField()
    term_status = serializers.SerializerMethodField()
    is_editable = serializers.SerializerMethodField()

    class Meta:
        model = StudentTeam
        fields = [
            'id',
            'name',
            'project_title',
            'level',
            'year_level',
            'semester_id',
            'semester',
            'school_year',
            'display_semester',
            'leader_id',
            'leader_username',
            'leader_name',
            'adviser_id',
            'adviser_username',
            'adviser_name',
            'member_ids',
            'members',
            'member_count',
            'status',
            'capstone_phase',
            'ready_for_stage',
            'current_defense_stage',
            'is_capstone',
            'deliverable_count',
            'defense_context',
            'term_status',
            'is_editable',
            'created_at',
            'updated_at',
        ]

    def get_leader_name(self, obj):
        return display_name(obj.leader)

    def get_adviser_name(self, obj):
        return display_name(obj.adviser)

    def get_member_ids(self, obj):
        return [membership.student_id for membership in obj.memberships.all()]

    def get_member_count(self, obj):
        return len(obj.memberships.all())

    def get_deliverable_count(self, obj):
        if not obj.is_capstone:
            return 0
        return obj.deliverable_submissions.count()

    def get_defense_context(self, obj):
        if obj.is_capstone:
            return {
                'is_pit': False,
                'current_stage': obj.current_defense_stage or obj.ready_for_stage or 'Concept Proposal',
                'ready_for_stage': obj.ready_for_stage,
                'deliverable_count': obj.deliverable_submissions.count(),
            }
        schedule = (
            DefenseSchedule.objects.filter(
                team=obj,
                scope=DefenseSchedule.SCOPE_PIT,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .order_by('scheduled_date', 'start_time')
            .first()
        )
        if schedule:
            return {
                'is_pit': True,
                'event_label': schedule.stage_label or 'PIT Event',
                'scheduled_date': schedule.scheduled_date.isoformat() if schedule.scheduled_date else '',
            }
        return {
            'is_pit': True,
            'event_label': 'No PIT event scheduled',
            'scheduled_date': '',
        }

    def get_term_status(self, obj):
        return term_status_for_team(obj)

    def get_is_editable(self, obj):
        user = self.context.get('user')
        if user is None:
            return False
        return team_is_editable(user, obj)


class StudentTeamWriteSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    project_title = serializers.CharField(required=False, allow_blank=True, max_length=255)
    level = serializers.ChoiceField(
        choices=[choice[0] for choice in StudentTeam.LEVEL_CHOICES],
        required=False,
        allow_blank=True,
    )
    year_level = serializers.CharField(required=False, allow_blank=True, max_length=20)
    semester_id = serializers.IntegerField(required=False)
    leader_id = serializers.IntegerField()
    member_ids = serializers.ListField(child=serializers.IntegerField(), min_length=1, max_length=4)
    adviser_id = serializers.IntegerField(required=False, allow_null=True)
    status = serializers.ChoiceField(
        choices=[choice[0] for choice in StudentTeam.STATUS_CHOICES],
        required=False,
    )
    capstone_phase = serializers.ChoiceField(
        choices=[choice[0] for choice in StudentTeam.PHASE_CHOICES],
        required=False,
        allow_null=True,
    )
    ready_for_stage = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=80)
    current_defense_stage = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=80)
    adviser_change_reason = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=255,
        write_only=True,
    )

    def validate(self, attrs):
        member_ids = list(dict.fromkeys(attrs['member_ids']))
        attrs['member_ids'] = member_ids

        if attrs['leader_id'] not in member_ids:
            raise serializers.ValidationError({'leader_id': 'Leader must be included in team members.'})

        members = list(User.objects.filter(pk__in=member_ids, role='student'))
        if len(members) != len(member_ids):
            raise serializers.ValidationError({'member_ids': 'All members must be valid student users.'})

        # Check if any student is already in another team
        team_id = self.context.get('team_id')  # Current team ID when updating
        
        for student_id in member_ids:
            # Find existing team memberships for this student in the active semester
            existing_memberships = TeamMembership.objects.filter(
                student_id=student_id,
                team__semester__is_active=True,
            )
            
            # If updating, exclude the current team
            if team_id:
                existing_memberships = existing_memberships.exclude(team_id=team_id)
            
            if existing_memberships.exists():
                # Get the student and their current team
                student = User.objects.get(pk=student_id)
                current_team = existing_memberships.first().team
                student_name = display_name(student)
                raise serializers.ValidationError({
                    'member_ids': f'{student_name} is already assigned to team "{current_team.name}". A student can only be in one team at a time.'
                })

        try:
            attrs['leader'] = User.objects.get(pk=attrs['leader_id'], role='student')
        except User.DoesNotExist as exc:
            raise serializers.ValidationError({'leader_id': 'Leader must be a valid student user.'}) from exc

        adviser_id = attrs.get('adviser_id')
        attrs['adviser'] = None
        if adviser_id:
            try:
                attrs['adviser'] = User.objects.get(pk=adviser_id, role__in=['faculty', 'admin'])
            except User.DoesNotExist as exc:
                raise serializers.ValidationError({'adviser_id': 'Adviser must be a valid faculty or admin user.'}) from exc

        semester = self._resolve_semester(attrs)
        attrs['semester'] = semester

        user = self.context.get('assigned_by') or self.context.get('user')
        assert_active_semester_for_create(user, semester)
        if self.instance is not None:
            assert_team_writable(user, self.instance)
        from academic_period_management.capstone_mode import assert_capstone_team_creation_allowed

        if user_is_admin(user) and self.instance is None:
            try:
                assert_capstone_team_creation_allowed(semester)
            except ValueError as exc:
                raise serializers.ValidationError({'non_field_errors': [str(exc)]}) from exc
        from .team_levels import normalize_year_level

        if user_is_admin(user) and not normalize_year_level(attrs.get('year_level', '')):
            inferred, year_issues = infer_year_level_from_members(
                member_ids,
                semester,
                leader_id=attrs['leader_id'],
            )
            if year_issues:
                raise serializers.ValidationError({'member_ids': year_issues})
            attrs['year_level'] = inferred

        if user and (user_is_admin(user) or user_is_pit_lead_only(user)):
            try:
                attrs['level'] = resolve_team_level(
                    user=user,
                    year_level=attrs.get('year_level', ''),
                    level=attrs.get('level', ''),
                    member_ids=member_ids,
                    semester=semester,
                    leader_id=attrs['leader_id'],
                )
            except ValueError as exc:
                raise serializers.ValidationError({'level': str(exc)}) from exc
        elif not attrs.get('level'):
            raise serializers.ValidationError({'level': 'This field is required.'})

        attrs['year_level'] = attrs.get('year_level') or team_level_year(attrs['level'])

        if user_is_admin(user) and 'PIT' in attrs['level']:
            raise serializers.ValidationError({'level': 'Admins can only manage capstone teams.'})
        if user_is_pit_lead_only(user) and 'Capstone' in attrs['level']:
            raise serializers.ValidationError({'level': 'PIT Leads can only manage PIT teams.'})

        existing = StudentTeam.objects.filter(name=attrs['name'], level=attrs['level'])
        team_id = self.context.get('team_id')
        if team_id:
            existing = existing.exclude(pk=team_id)
        if existing.exists():
            raise serializers.ValidationError({'name': 'A team with this name already exists for this level.'})

        return attrs

    @transaction.atomic
    def create(self, validated_data):
        member_ids = validated_data.pop('member_ids')
        reason = validated_data.pop('adviser_change_reason', '')
        team = StudentTeam.objects.create(
            name=validated_data['name'],
            project_title=validated_data.get('project_title') or validated_data['name'],
            level=validated_data['level'],
            year_level=validated_data['year_level'],
            semester=validated_data['semester'],
            leader=validated_data['leader'],
            adviser=validated_data.get('adviser'),
            status=validated_data.get('status', StudentTeam.STATUS_PENDING),
            capstone_phase=validated_data.get('capstone_phase'),
            ready_for_stage=validated_data.get('ready_for_stage') or None,
            current_defense_stage=validated_data.get('current_defense_stage') or None,
        )
        self._sync_members(team, member_ids, validated_data['leader'].id)
        record_team_adviser_change(
            team,
            None,
            team.adviser,
            assigned_by=self.context.get('assigned_by'),
            reason=reason,
        )
        return team

    @transaction.atomic
    def update(self, instance, validated_data):
        member_ids = validated_data.pop('member_ids')
        reason = validated_data.pop('adviser_change_reason', '')
        previous_adviser_id = instance.adviser_id
        instance.name = validated_data['name']
        instance.project_title = validated_data.get('project_title') or validated_data['name']
        instance.level = validated_data['level']
        instance.year_level = validated_data['year_level']
        instance.semester = validated_data['semester']
        instance.leader = validated_data['leader']
        instance.adviser = validated_data.get('adviser')
        instance.status = validated_data.get('status', instance.status)
        instance.capstone_phase = validated_data.get('capstone_phase')
        instance.ready_for_stage = validated_data.get('ready_for_stage') or None
        instance.current_defense_stage = validated_data.get('current_defense_stage') or None
        instance.save()
        self._sync_members(instance, member_ids, validated_data['leader'].id)
        record_team_adviser_change(
            instance,
            previous_adviser_id,
            instance.adviser,
            assigned_by=self.context.get('assigned_by'),
            reason=reason,
        )
        return instance

    def _resolve_semester(self, attrs):
        active = Semester.objects.select_related('school_year').filter(is_active=True).first()
        if active is None:
            raise serializers.ValidationError({'semester_id': 'No active semester is configured.'})

        semester_id = attrs.get('semester_id')
        if semester_id and semester_id != active.id:
            raise serializers.ValidationError({
                'semester_id': 'Teams can only be created or updated on the active semester.',
            })

        return active

    def _sync_members(self, team, member_ids, leader_id):
        # Remove old memberships for this team
        team.memberships.all().delete()
        
        # Remove students from any other teams they might be in
        # This ensures a student is only in one team at a time
        TeamMembership.objects.filter(student_id__in=member_ids).exclude(team=team).delete()
        
        # Create new memberships
        memberships = [
            TeamMembership(
                team=team,
                student_id=student_id,
                is_leader=student_id == leader_id,
                order=index,
            )
            for index, student_id in enumerate(member_ids)
        ]
        TeamMembership.objects.bulk_create(memberships)
        
        # Update user team_id field
        User.objects.filter(pk__in=member_ids).update(team_id=str(team.id))


class BulkTeamRowSerializer(serializers.Serializer):
    team_name = serializers.CharField(max_length=120)
    project_title = serializers.CharField(required=False, allow_blank=True, max_length=255)
    level = serializers.CharField(required=False, allow_blank=True, max_length=30)
    year_level = serializers.CharField(required=False, allow_blank=True, max_length=20)
    member_ids = serializers.ListField(child=serializers.CharField(), min_length=1, max_length=4)
    leader_id = serializers.CharField()
    adviser_id = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        user = self.context.get('user')
        if user:
            try:
                attrs['level'] = resolve_team_level(
                    user=user,
                    year_level=attrs.get('year_level', ''),
                    level=attrs.get('level', ''),
                )
            except ValueError as exc:
                raise serializers.ValidationError({'level': str(exc)}) from exc
            attrs['year_level'] = team_level_year(attrs['level'])
        elif not (attrs.get('level') or '').strip():
            raise serializers.ValidationError({'level': 'This field is required.'})
        return attrs


class TeamAdviserAssignmentSerializer(serializers.ModelSerializer):
    team_id = serializers.IntegerField(source='team.id', read_only=True)
    team_name = serializers.CharField(source='team.name', read_only=True)
    project_title = serializers.CharField(source='team.project_title', read_only=True)
    team_level = serializers.CharField(source='team.level', read_only=True)
    year_level = serializers.CharField(source='team.year_level', read_only=True)
    semester = serializers.CharField(source='team.semester.display_name', read_only=True)
    adviser_id = serializers.IntegerField(source='adviser.id', read_only=True, allow_null=True)
    adviser_name = serializers.SerializerMethodField()
    assigned_by_id = serializers.IntegerField(source='assigned_by.id', read_only=True, allow_null=True)
    assigned_by_name = serializers.SerializerMethodField()
    is_current = serializers.SerializerMethodField()

    class Meta:
        model = TeamAdviserAssignment
        fields = [
            'id',
            'team_id',
            'team_name',
            'project_title',
            'team_level',
            'year_level',
            'semester',
            'adviser_id',
            'adviser_name',
            'assigned_by_id',
            'assigned_by_name',
            'assigned_at',
            'ended_at',
            'reason',
            'is_current',
        ]

    def get_adviser_name(self, obj):
        return display_name(obj.adviser) if obj.adviser_id else 'Unassigned'

    def get_assigned_by_name(self, obj):
        return display_name(obj.assigned_by) if obj.assigned_by_id else None

    def get_is_current(self, obj):
        return obj.ended_at is None


class StudentTeamOptionsSerializer(serializers.Serializer):
    active_semester = SemesterSerializer(allow_null=True)
    students = StudentOptionSerializer(many=True)
    advisers = AdviserOptionSerializer(many=True)
