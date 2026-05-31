import uuid
from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.db import transaction
from rest_framework import serializers

from academic_period_management.models import Semester
from defense.stages.grading_config import get_or_create_stage_grading_config
from academic_period_management.serializers import SemesterSerializer
from defense.stages.models import DefenseStage
from defense.stages.serializers import DefenseStageSerializer
from grading.rubrics.models import Rubric
from grading.rubrics.serializers import RubricSerializer
from student_teams.models import StudentTeam
from student_teams.services import get_ready_teams, is_stage_ready, mark_stage_scheduled
from .models import DefenseSchedule, SchedulePanelist
from .pit_config import get_pit_event_config, pit_event_config_payload, upsert_pit_event_config


User = get_user_model()
ACTIVE_STATUSES = [DefenseSchedule.STATUS_SCHEDULED]


def time_to_minutes(value):
    return value.hour * 60 + value.minute


def schedule_interval(start_time, slot_duration):
    start_minutes = time_to_minutes(start_time)
    return start_minutes, start_minutes + slot_duration


def intervals_overlap(start_minutes, end_minutes, other_start_minutes, other_end_minutes):
    return start_minutes < other_end_minutes and other_start_minutes < end_minutes


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def schedule_queryset():
    return (
        DefenseSchedule.objects.select_related(
            'semester',
            'semester__school_year',
            'team',
            'team__leader',
            'team__adviser',
            'defense_stage',
            'rubric',
            'created_by',
        )
        .prefetch_related('panel_assignments', 'panel_assignments__panelist')
    )


class PanelistOptionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'name', 'email']

    def get_name(self, obj):
        return display_name(obj)


class ScheduleTeamSerializer(serializers.ModelSerializer):
    leader_name = serializers.SerializerMethodField()
    adviser_name = serializers.SerializerMethodField()
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)

    class Meta:
        model = StudentTeam
        fields = [
            'id',
            'name',
            'project_title',
            'level',
            'year_level',
            'status',
            'ready_for_stage',
            'current_defense_stage',
            'display_semester',
            'leader_name',
            'adviser_name',
        ]

    def get_leader_name(self, obj):
        return display_name(obj.leader)

    def get_adviser_name(self, obj):
        return display_name(obj.adviser)


class SchedulePanelistSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(source='panelist.id', read_only=True)
    username = serializers.CharField(source='panelist.username', read_only=True)
    name = serializers.SerializerMethodField()
    email = serializers.EmailField(source='panelist.email', read_only=True)

    class Meta:
        model = SchedulePanelist
        fields = ['id', 'username', 'name', 'email', 'order']

    def get_name(self, obj):
        return display_name(obj.panelist)


class DefenseScheduleSerializer(serializers.ModelSerializer):
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)
    team_id = serializers.IntegerField(source='team.id', read_only=True)
    team_name = serializers.CharField(source='team.name', read_only=True)
    project_title = serializers.CharField(source='team.project_title', read_only=True)
    team_level = serializers.CharField(source='team.level', read_only=True)
    defense_stage_id = serializers.IntegerField(source='defense_stage.id', read_only=True, allow_null=True)
    defense_stage_label = serializers.CharField(source='defense_stage.label', read_only=True, allow_null=True)
    pit_event_config_id = serializers.SerializerMethodField()
    stage_label = serializers.CharField(read_only=True)
    rubric_id = serializers.IntegerField(source='rubric.id', read_only=True, allow_null=True)
    rubric_name = serializers.CharField(source='rubric.name', read_only=True, allow_null=True)
    panelists = SchedulePanelistSerializer(source='panel_assignments', many=True, read_only=True)
    panelist_ids = serializers.SerializerMethodField()
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = DefenseSchedule
        fields = [
            'id',
            'batch_id',
            'scope',
            'semester_id',
            'display_semester',
            'team_id',
            'team_name',
            'project_title',
            'team_level',
            'defense_stage_id',
            'defense_stage_label',
            'pit_event_config_id',
            'event_name',
            'stage_label',
            'rubric_id',
            'rubric_name',
            'scheduled_date',
            'start_time',
            'slot_duration',
            'room',
            'status',
            'panelists',
            'panelist_ids',
            'created_by_name',
            'created_at',
            'updated_at',
        ]

    def get_panelist_ids(self, obj):
        return [assignment.panelist_id for assignment in obj.panel_assignments.all()]

    def get_pit_event_config_id(self, obj):
        if obj.scope != DefenseSchedule.SCOPE_PIT:
            return None
        config = get_pit_event_config(obj.semester, obj.event_name)
        return config.id if config else None

    def get_created_by_name(self, obj):
        return display_name(obj.created_by)


class ScheduleBaseSerializer(serializers.Serializer):
    scope = serializers.ChoiceField(
        choices=[choice[0] for choice in DefenseSchedule.SCOPE_CHOICES],
        default=DefenseSchedule.SCOPE_CAPSTONE,
    )
    semester_id = serializers.IntegerField(required=False)
    defense_stage_id = serializers.IntegerField(required=False, allow_null=True)
    event_name = serializers.CharField(required=False, allow_blank=True, max_length=120)
    rubric_id = serializers.IntegerField(required=False, allow_null=True)
    peer_rubric_id = serializers.IntegerField(required=False, allow_null=True)
    panel_weight = serializers.IntegerField(required=False, min_value=0, max_value=100)
    peer_weight = serializers.IntegerField(required=False, min_value=0, max_value=100)
    scheduled_date = serializers.DateField()
    start_time = serializers.TimeField()
    slot_duration = serializers.IntegerField(min_value=15, max_value=240, default=60)
    room = serializers.CharField(max_length=120)
    panelist_ids = serializers.ListField(child=serializers.IntegerField(), min_length=1)
    vault_file_template = serializers.CharField(required=False, allow_blank=True, max_length=255)

    def validate(self, attrs):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user and getattr(user, 'is_pit_lead', False) and getattr(user, 'role', None) != 'admin':
            attrs['scope'] = DefenseSchedule.SCOPE_PIT

        attrs['room'] = attrs['room'].strip()
        attrs['event_name'] = (attrs.get('event_name') or '').strip()
        attrs['semester'] = self._resolve_semester(attrs)
        attrs['defense_stage'] = self._resolve_defense_stage(attrs)
        attrs['panelists'] = self._resolve_panelists(attrs['panelist_ids'])
        attrs['rubric'] = self._resolve_rubric(attrs)
        if attrs['scope'] == DefenseSchedule.SCOPE_PIT:
            attrs = self._validate_pit_event_setup(attrs)
        else:
            attrs = self._validate_capstone_stage_setup(attrs)
        return attrs

    def _validate_capstone_stage_setup(self, attrs):
        if not attrs.get('rubric'):
            raise serializers.ValidationError({'rubric_id': 'Capstone schedules require a panel rubric.'})

        config = get_or_create_stage_grading_config(attrs['defense_stage'], attrs['semester'])
        if config is None:
            raise serializers.ValidationError({'defense_stage_id': 'Stage grading configuration is required.'})

        missing = []
        if not config.panel_rubric_id:
            missing.append('panel')
        if not config.adviser_rubric_id:
            missing.append('adviser')
        if not config.peer_rubric_id:
            missing.append('peer')
        if missing:
            raise serializers.ValidationError({
                'rubric_id': (
                    'Assign published panel, adviser, and peer rubrics for this '
                    f'stage before scheduling. Missing: {", ".join(missing)}.'
                ),
            })

        if attrs['rubric'].id != config.panel_rubric_id:
            raise serializers.ValidationError({
                'rubric_id': 'Panel rubric must match the stage grading configuration.',
            })

        return attrs

    def _validate_pit_event_setup(self, attrs):
        if not attrs.get('rubric'):
            raise serializers.ValidationError({'rubric_id': 'PIT schedules require a panel rubric.'})

        peer_rubric = self._resolve_peer_rubric(attrs)
        if peer_rubric is None:
            raise serializers.ValidationError({'peer_rubric_id': 'PIT schedules require a peer rubric.'})

        panel_weight = attrs.get('panel_weight')
        peer_weight = attrs.get('peer_weight')
        if panel_weight is None or peer_weight is None:
            existing = get_pit_event_config(attrs['semester'], attrs['event_name'])
            if existing is not None:
                panel_weight = existing.panel_weight if panel_weight is None else panel_weight
                peer_weight = existing.peer_weight if peer_weight is None else peer_weight
            else:
                panel_weight = panel_weight if panel_weight is not None else 80
                peer_weight = peer_weight if peer_weight is not None else 20

        if panel_weight + peer_weight != 100:
            raise serializers.ValidationError(
                'Panel and peer weights must total 100%.',
            )

        attrs['peer_rubric'] = peer_rubric
        attrs['panel_weight'] = panel_weight
        attrs['peer_weight'] = peer_weight
        attrs['pit_event_config'] = upsert_pit_event_config(
            semester=attrs['semester'],
            event_name=attrs['event_name'],
            panel_rubric=attrs['rubric'],
            peer_rubric=peer_rubric,
            panel_weight=panel_weight,
            peer_weight=peer_weight,
            vault_file_template=attrs.get('vault_file_template'),
        )
        return attrs

    def _resolve_peer_rubric(self, attrs):
        peer_rubric_id = attrs.get('peer_rubric_id')
        if not peer_rubric_id:
            return None

        try:
            rubric = Rubric.objects.get(pk=peer_rubric_id)
        except Rubric.DoesNotExist as exc:
            raise serializers.ValidationError({'peer_rubric_id': 'Peer rubric does not exist.'}) from exc

        if rubric.status != Rubric.STATUS_PUBLISHED:
            raise serializers.ValidationError({'peer_rubric_id': 'Scheduler can only use published rubrics.'})
        if rubric.evaluation_type != Rubric.EVAL_PEER:
            raise serializers.ValidationError({'peer_rubric_id': 'Peer rubric must use peer evaluation type.'})
        if rubric.scope != DefenseSchedule.SCOPE_PIT:
            raise serializers.ValidationError({'peer_rubric_id': 'Peer rubric scope must be PIT.'})
        return rubric

    def _resolve_semester(self, attrs):
        semester_id = attrs.get('semester_id')
        if semester_id:
            try:
                return Semester.objects.select_related('school_year').get(pk=semester_id)
            except Semester.DoesNotExist as exc:
                raise serializers.ValidationError({'semester_id': 'Semester does not exist.'}) from exc

        semester = active_semester()
        if semester is None:
            raise serializers.ValidationError({'semester_id': 'No active semester is configured.'})
        return semester

    def _resolve_defense_stage(self, attrs):
        scope = attrs['scope']
        if scope == DefenseSchedule.SCOPE_PIT:
            if not attrs.get('event_name'):
                raise serializers.ValidationError({'event_name': 'PIT schedules require an event name.'})
            return None

        stage_id = attrs.get('defense_stage_id')
        if not stage_id:
            raise serializers.ValidationError({'defense_stage_id': 'Capstone schedules require a defense stage.'})
        try:
            return DefenseStage.objects.get(pk=stage_id, is_active=True)
        except DefenseStage.DoesNotExist as exc:
            raise serializers.ValidationError({'defense_stage_id': 'Defense stage does not exist or is inactive.'}) from exc

    def _resolve_panelists(self, panelist_ids):
        unique_ids = list(dict.fromkeys(panelist_ids))
        panelists = list(
            User.objects.filter(
                pk__in=unique_ids,
                role__in=['faculty', 'admin'],
                is_panelist=True,
                is_active=True,
            )
        )
        if len(panelists) != len(unique_ids):
            raise serializers.ValidationError({'panelist_ids': 'All panelists must be assigned faculty panelists.'})
        panelists.sort(key=lambda item: unique_ids.index(item.id))
        return panelists

    def _resolve_rubric(self, attrs):
        rubric_id = attrs.get('rubric_id')
        if not rubric_id:
            return None

        try:
            rubric = Rubric.objects.select_related('defense_stage').get(pk=rubric_id)
        except Rubric.DoesNotExist as exc:
            raise serializers.ValidationError({'rubric_id': 'Rubric does not exist.'}) from exc

        if rubric.status != Rubric.STATUS_PUBLISHED:
            raise serializers.ValidationError({'rubric_id': 'Scheduler can only use published rubrics.'})
        if rubric.evaluation_type != Rubric.EVAL_PANEL:
            raise serializers.ValidationError({'rubric_id': 'Scheduler can only use panel rubrics.'})
        if rubric.scope != attrs['scope']:
            raise serializers.ValidationError({'rubric_id': 'Rubric scope must match the schedule scope.'})
        if attrs['scope'] == DefenseSchedule.SCOPE_CAPSTONE and rubric.defense_stage_id != attrs['defense_stage'].id:
            raise serializers.ValidationError({'rubric_id': 'Rubric defense stage must match the selected stage.'})
        return rubric

    def _context_filter(self, attrs):
        queryset = DefenseSchedule.objects.filter(
            scope=attrs['scope'],
            semester=attrs['semester'],
            status__in=ACTIVE_STATUSES,
        )
        if attrs['scope'] == DefenseSchedule.SCOPE_PIT:
            return queryset.filter(event_name__iexact=attrs['event_name'])
        return queryset.filter(defense_stage=attrs['defense_stage'])

    def _slot_interval(self, attrs, index=0):
        start_minutes, _end_minutes = schedule_interval(attrs['start_time'], attrs['slot_duration'])
        slot_start = start_minutes + (attrs['slot_duration'] * index)
        return slot_start, slot_start + attrs['slot_duration']

    def _schedule_overlaps(self, schedule, start_minutes, end_minutes):
        other_start, other_end = schedule_interval(schedule.start_time, schedule.slot_duration)
        return intervals_overlap(start_minutes, end_minutes, other_start, other_end)

    def _validate_room_overlap(self, attrs, slot_intervals, error_field='start_time'):
        schedules = DefenseSchedule.objects.filter(
            scheduled_date=attrs['scheduled_date'],
            room__iexact=attrs['room'],
            status__in=ACTIVE_STATUSES,
        )
        for start_minutes, end_minutes in slot_intervals:
            if any(self._schedule_overlaps(schedule, start_minutes, end_minutes) for schedule in schedules):
                raise serializers.ValidationError({
                    error_field: 'This room already has an active schedule during that time.',
                })

    def _validate_panelist_overlap(self, attrs, slot_intervals, error_field='panelist_ids'):
        panelist_ids = {panelist.id for panelist in attrs['panelists']}
        schedules = (
            DefenseSchedule.objects.filter(
                scheduled_date=attrs['scheduled_date'],
                panel_assignments__panelist_id__in=panelist_ids,
                status__in=ACTIVE_STATUSES,
            )
            .prefetch_related('panel_assignments')
            .distinct()
        )
        for start_minutes, end_minutes in slot_intervals:
            for schedule in schedules:
                if not self._schedule_overlaps(schedule, start_minutes, end_minutes):
                    continue
                scheduled_panelist_ids = {
                    assignment.panelist_id
                    for assignment in schedule.panel_assignments.all()
                }
                if panelist_ids & scheduled_panelist_ids:
                    raise serializers.ValidationError({
                        error_field: 'A selected panelist already has an active schedule during that time.',
                    })

    def _validate_internal_slot_overlaps(self, slot_intervals):
        for index, (start_minutes, end_minutes) in enumerate(slot_intervals):
            for other_start, other_end in slot_intervals[index + 1:]:
                if intervals_overlap(start_minutes, end_minutes, other_start, other_end):
                    raise serializers.ValidationError({
                        'slots': 'Schedule plan contains overlapping slots.',
                    })


class DefenseScheduleWriteSerializer(ScheduleBaseSerializer):
    team_id = serializers.IntegerField()
    status = serializers.ChoiceField(
        choices=[choice[0] for choice in DefenseSchedule.STATUS_CHOICES],
        default=DefenseSchedule.STATUS_SCHEDULED,
        required=False,
    )

    def validate(self, attrs):
        attrs = super().validate(attrs)
        attrs['team'] = self._resolve_team(attrs)
        self._validate_duplicate(attrs)
        slot_intervals = [self._slot_interval(attrs)]
        self._validate_room_overlap(attrs, slot_intervals)
        self._validate_panelist_overlap(attrs, slot_intervals)
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        panelists = validated_data.pop('panelists')
        self._pop_schedule_meta(validated_data)
        schedule = DefenseSchedule.objects.create(
            **validated_data,
            created_by=getattr(self.context.get('request'), 'user', None),
        )
        self._sync_panelists(schedule, panelists)
        self._sync_grade_row(schedule)
        return schedule

    def _pop_schedule_meta(self, validated_data):
        validated_data.pop('panelist_ids', None)
        validated_data.pop('defense_stage_id', None)
        validated_data.pop('rubric_id', None)
        validated_data.pop('peer_rubric_id', None)
        validated_data.pop('panel_weight', None)
        validated_data.pop('peer_weight', None)
        validated_data.pop('vault_file_template', None)
        validated_data.pop('peer_rubric', None)
        validated_data.pop('pit_event_config', None)
        validated_data.pop('semester_id', None)
        validated_data.pop('team_id', None)

    def _sync_grade_row(self, schedule):
        from grading.grades.services import _sync_grade_for_schedule

        grade, _created, _changed = _sync_grade_for_schedule(schedule)
        if schedule.scope == DefenseSchedule.SCOPE_CAPSTONE:
            mark_stage_scheduled(
                schedule.team,
                schedule.defense_stage,
                grade=grade,
                user=getattr(self.context.get('request'), 'user', None),
            )

    def _resolve_team(self, attrs):
        try:
            team = (
                StudentTeam.objects.select_related('semester', 'leader', 'adviser')
                .get(pk=attrs['team_id'], semester=attrs['semester'])
            )
        except StudentTeam.DoesNotExist as exc:
            raise serializers.ValidationError({'team_id': 'Team does not exist for the selected semester.'}) from exc

        if attrs['scope'] == DefenseSchedule.SCOPE_CAPSTONE and not team.is_capstone:
            raise serializers.ValidationError({'team_id': 'Capstone schedules require a Capstone team.'})
        if attrs['scope'] == DefenseSchedule.SCOPE_CAPSTONE and not is_stage_ready(team, attrs['defense_stage']):
            raise serializers.ValidationError({'team_id': 'Team is not endorsed for this stage.'})
        if attrs['scope'] == DefenseSchedule.SCOPE_PIT and not team.is_pit:
            raise serializers.ValidationError({'team_id': 'PIT schedules require a PIT team.'})
        return team

    def _validate_duplicate(self, attrs):
        queryset = DefenseSchedule.objects.filter(
            scope=attrs['scope'],
            semester=attrs['semester'],
            team=attrs['team'],
            status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
        )
        if attrs['scope'] == DefenseSchedule.SCOPE_PIT:
            queryset = queryset.filter(event_name__iexact=attrs['event_name'])
        else:
            queryset = queryset.filter(defense_stage=attrs['defense_stage'])
        if queryset.exists():
            raise serializers.ValidationError({'team_id': 'This team already has a scheduled or completed defense for this stage or event.'})

    def _sync_panelists(self, schedule, panelists):
        SchedulePanelist.objects.bulk_create([
            SchedulePanelist(schedule=schedule, panelist=panelist, order=index)
            for index, panelist in enumerate(panelists)
        ])


class GenerateSchedulePlanSerializer(ScheduleBaseSerializer):
    def _validate_capstone_stage_setup(self, attrs):
        # Frontend syncs Capstone rubrics to StageGradingConfig immediately *before* 
        # calling confirm-plan. During generate-plan, the config might be incomplete, 
        # so we only require the panel rubric from the form payload.
        if not attrs.get('rubric'):
            raise serializers.ValidationError({'rubric_id': 'Capstone schedules require a panel rubric.'})
        return attrs

    def generate_slots(self):
        attrs = self.validated_data
        teams = self._ready_teams(attrs)
        start_minutes = attrs['start_time'].hour * 60 + attrs['start_time'].minute
        slots = []

        for index, team in enumerate(teams):
            slot_start = minutes_to_time(start_minutes + attrs['slot_duration'] * index)
            slot_end = minutes_to_time(start_minutes + attrs['slot_duration'] * (index + 1))
            slots.append({
                'slot': index + 1,
                'team_id': team.id,
                'team_name': team.name,
                'project_title': team.project_title,
                'team_level': team.level,
                'stage_label': attrs['event_name'] if attrs['scope'] == DefenseSchedule.SCOPE_PIT else attrs['defense_stage'].label,
                'scheduled_date': attrs['scheduled_date'],
                'start_time': slot_start,
                'end_time': slot_end,
                'slot_duration': attrs['slot_duration'],
                'room': attrs['room'],
                'panelists': PanelistOptionSerializer(attrs['panelists'], many=True).data,
            })
        return slots

    def _ready_teams(self, attrs):
        queryset = StudentTeam.objects.select_related('semester', 'leader', 'adviser').filter(semester=attrs['semester'])
        scheduled_team_ids = set(self._context_filter(attrs).values_list('team_id', flat=True))

        if attrs['scope'] == DefenseSchedule.SCOPE_CAPSTONE:
            ready_ids = get_ready_teams(attrs['semester'], attrs['defense_stage']).values_list('id', flat=True)
            queryset = queryset.filter(level__icontains='Capstone', id__in=ready_ids)
        else:
            queryset = queryset.filter(level__icontains='PIT')
            queryset = queryset.exclude(year_level='3rd Year', semester__label=Semester.SECOND)

        return list(queryset.exclude(pk__in=scheduled_team_ids).order_by('name'))


class ConfirmSchedulePlanSerializer(ScheduleBaseSerializer):
    slots = serializers.ListField(child=serializers.DictField(), min_length=1)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        team_ids = []
        for slot in attrs['slots']:
            team_id = slot.get('team_id')
            if team_id is None:
                raise serializers.ValidationError({'slots': 'Every slot requires team_id.'})
            team_ids.append(int(team_id))
        if len(team_ids) != len(set(team_ids)):
            raise serializers.ValidationError({'slots': 'A team can only appear once in a schedule plan.'})

        teams = StudentTeam.objects.select_related('semester').filter(pk__in=team_ids, semester=attrs['semester'])
        team_map = {team.id: team for team in teams}
        if len(team_map) != len(team_ids):
            raise serializers.ValidationError({'slots': 'All slots must use teams from the selected semester.'})

        for team_id in team_ids:
            team = team_map[team_id]
            if attrs['scope'] == DefenseSchedule.SCOPE_CAPSTONE:
                if not team.is_capstone:
                    raise serializers.ValidationError({'slots': 'Capstone plans can only include Capstone teams.'})
                if not is_stage_ready(team, attrs['defense_stage']):
                    raise serializers.ValidationError({'slots': f'{team.name} is not endorsed for this stage.'})
            elif not team.is_pit:
                raise serializers.ValidationError({'slots': 'PIT plans can only include PIT teams.'})

            existing = DefenseSchedule.objects.filter(
                scope=attrs['scope'],
                semester=attrs['semester'],
                team=team,
                status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
            )
            if attrs['scope'] == DefenseSchedule.SCOPE_PIT:
                existing = existing.filter(event_name__iexact=attrs['event_name'])
            else:
                existing = existing.filter(defense_stage=attrs['defense_stage'])
            if existing.exists():
                raise serializers.ValidationError({'slots': f'{team.name} already has a scheduled or completed defense for this stage or event.'})

        attrs['teams'] = [team_map[team_id] for team_id in team_ids]
        slot_intervals = [
            self._slot_interval(attrs, index)
            for index, _team in enumerate(attrs['teams'])
        ]
        self._validate_internal_slot_overlaps(slot_intervals)
        self._validate_room_overlap(attrs, slot_intervals, error_field='slots')
        self._validate_panelist_overlap(attrs, slot_intervals, error_field='slots')
        return attrs

    @transaction.atomic
    def save(self):
        attrs = self.validated_data
        batch_id = uuid.uuid4()
        start_minutes = attrs['start_time'].hour * 60 + attrs['start_time'].minute
        schedules = []
        for index, team in enumerate(attrs['teams']):
            schedule = DefenseSchedule.objects.create(
                batch_id=batch_id,
                scope=attrs['scope'],
                semester=attrs['semester'],
                team=team,
                defense_stage=attrs.get('defense_stage'),
                event_name=attrs.get('event_name', ''),
                rubric=attrs.get('rubric'),
                scheduled_date=attrs['scheduled_date'],
                start_time=minutes_to_time(start_minutes + attrs['slot_duration'] * index),
                slot_duration=attrs['slot_duration'],
                room=attrs['room'],
                status=DefenseSchedule.STATUS_SCHEDULED,
                created_by=getattr(self.context.get('request'), 'user', None),
            )
            SchedulePanelist.objects.bulk_create([
                SchedulePanelist(schedule=schedule, panelist=panelist, order=order)
                for order, panelist in enumerate(attrs['panelists'])
            ])
            schedules.append(schedule)
        from grading.grades.services import _sync_grade_for_schedule

        for schedule in schedules:
            grade, _created, _changed = _sync_grade_for_schedule(schedule)
            if schedule.scope == DefenseSchedule.SCOPE_CAPSTONE:
                mark_stage_scheduled(
                    schedule.team,
                    schedule.defense_stage,
                    grade=grade,
                    user=getattr(self.context.get('request'), 'user', None),
                )
        return schedules


class DefenseScheduleStatusSerializer(serializers.Serializer):
    VALID_TRANSITIONS = {
        DefenseSchedule.STATUS_SCHEDULED: [
            DefenseSchedule.STATUS_DONE,
            DefenseSchedule.STATUS_CANCELLED,
        ],
        DefenseSchedule.STATUS_DONE: [
            DefenseSchedule.STATUS_ARCHIVED,
        ],
        DefenseSchedule.STATUS_CANCELLED: [
            DefenseSchedule.STATUS_SCHEDULED,
        ],
        DefenseSchedule.STATUS_ARCHIVED: [],
    }

    status = serializers.ChoiceField(choices=[choice[0] for choice in DefenseSchedule.STATUS_CHOICES])

    def validate_status(self, value):
        current = self.context['schedule'].status
        allowed = self.VALID_TRANSITIONS.get(current, [])
        if value == current:
            return value
        if value not in allowed:
            raise serializers.ValidationError(
                f'Cannot change status from "{current}" to "{value}".'
            )
        return value

    def save(self):
        schedule = self.context['schedule']
        schedule.status = self.validated_data['status']
        schedule.save()
        return schedule



def minutes_to_time(minutes):
    base = datetime(2000, 1, 1)
    value = base + timedelta(minutes=minutes)
    return value.time().replace(second=0, microsecond=0)


def schedule_options_payload(user=None):
    from authentication_access_control.scopes import is_pit_lead_only, visible_teams_for

    semester = active_semester()
    stages = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label')
    rubrics = (
        Rubric.objects.select_related('semester', 'semester__school_year', 'defense_stage', 'created_by')
        .filter(status=Rubric.STATUS_PUBLISHED)
        .filter(
            Q(scope=Rubric.SCOPE_CAPSTONE)
            | Q(scope=Rubric.SCOPE_PIT, evaluation_type=Rubric.EVAL_PANEL)
        )
        .order_by('scope', 'defense_stage__display_order', 'name')
    )
    peer_rubrics = (
        Rubric.objects.select_related('semester', 'semester__school_year', 'created_by')
        .filter(status=Rubric.STATUS_PUBLISHED, scope=Rubric.SCOPE_PIT, evaluation_type=Rubric.EVAL_PEER)
        .order_by('name')
    )
    if is_pit_lead_only(user):
        stages = stages.none()
        rubrics = rubrics.filter(scope=Rubric.SCOPE_PIT)
        peer_rubrics = peer_rubrics.filter(scope=Rubric.SCOPE_PIT)
    panelists = User.objects.filter(role__in=['faculty', 'admin'], is_panelist=True, is_active=True).order_by('last_name', 'first_name', 'username')
    teams = visible_teams_for(user) if user else StudentTeam.objects.select_related('semester', 'leader', 'adviser')
    if semester:
        teams = teams.filter(semester=semester)
    else:
        teams = teams.none()

    return {
        'active_semester': SemesterSerializer(semester).data if semester else None,
        'defense_stages': DefenseStageSerializer(stages, many=True).data,
        'rubrics': RubricSerializer(rubrics, many=True).data,
        'peer_rubrics': RubricSerializer(peer_rubrics, many=True).data,
        'panelists': PanelistOptionSerializer(panelists, many=True).data,
        'teams': ScheduleTeamSerializer(teams, many=True).data,
        'scopes': [
            {'value': key, 'label': label}
            for key, label in DefenseSchedule.SCOPE_CHOICES
        ],
        'statuses': [choice[0] for choice in DefenseSchedule.STATUS_CHOICES],
    }
