import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class DefenseSchedule(models.Model):
    SCOPE_CAPSTONE = 'capstone'
    SCOPE_PIT = 'pit'

    SCOPE_CHOICES = (
        (SCOPE_CAPSTONE, 'Capstone'),
        (SCOPE_PIT, 'PIT'),
    )

    STATUS_SCHEDULED = 'scheduled'
    STATUS_DONE = 'done'
    STATUS_CANCELLED = 'cancelled'
    STATUS_ARCHIVED = 'archived'

    STATUS_CHOICES = (
        (STATUS_SCHEDULED, 'Scheduled'),
        (STATUS_DONE, 'Done'),
        (STATUS_CANCELLED, 'Cancelled'),
        (STATUS_ARCHIVED, 'Archived'),
    )

    batch_id = models.UUIDField(default=uuid.uuid4, editable=False, db_index=True)
    scope = models.CharField(max_length=20, choices=SCOPE_CHOICES, default=SCOPE_CAPSTONE)
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='defense_schedules',
        on_delete=models.PROTECT,
    )
    team = models.ForeignKey(
        'student_teams.StudentTeam',
        related_name='defense_schedules',
        on_delete=models.CASCADE,
    )
    defense_stage = models.ForeignKey(
        'defense.DefenseStage',
        related_name='defense_schedules',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
    event_name = models.CharField(max_length=120, blank=True)
    rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='defense_schedules',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    scheduled_date = models.DateField()
    start_time = models.TimeField()
    slot_duration = models.PositiveSmallIntegerField(default=60)
    room = models.CharField(max_length=120)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_SCHEDULED)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='created_defense_schedules',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    panelists = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        related_name='panel_defense_schedules',
        through='SchedulePanelist',
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_scheduler_schedule'
        ordering = ['scheduled_date', 'start_time', 'team__name']
        indexes = [
            models.Index(fields=['scheduled_date', 'status'], name='defense_sch_schedul_idx'),
            models.Index(fields=['scope', 'status'], name='defense_sch_scope_idx'),
            models.Index(fields=['room', 'scheduled_date', 'start_time'], name='defense_sch_room_idx'),
        ]

    @property
    def stage_label(self):
        if self.scope == self.SCOPE_PIT:
            return self.event_name
        return self.defense_stage.label if self.defense_stage else ''

    def clean(self):
        errors = {}
        if self.slot_duration < 15:
            errors['slot_duration'] = 'Slot duration must be at least 15 minutes.'
        if not self.room.strip():
            errors['room'] = 'Room is required.'

        if self.scope == self.SCOPE_CAPSTONE:
            if not self.defense_stage_id:
                errors['defense_stage'] = 'Capstone schedules require a defense stage.'
            if self.team_id and not self.team.is_capstone:
                errors['team'] = 'Capstone schedules require a Capstone team.'
        if self.scope == self.SCOPE_PIT:
            if not self.event_name.strip():
                errors['event_name'] = 'PIT schedules require an event name.'
            if self.team_id and not self.team.is_pit:
                errors['team'] = 'PIT schedules require a PIT team.'

        if self.rubric_id:
            if self.rubric.status != 'published':
                errors['rubric'] = 'Scheduler can only use published rubrics.'
            if self.rubric.evaluation_type != 'panel':
                errors['rubric'] = 'Scheduler can only use panel rubrics.'
            if self.rubric.scope != self.scope:
                errors['rubric'] = 'Rubric scope must match the schedule scope.'
            if self.scope == self.SCOPE_CAPSTONE and self.rubric.defense_stage_id != self.defense_stage_id:
                errors['rubric'] = 'Rubric defense stage must match the schedule stage.'

        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        if self.scope == self.SCOPE_PIT:
            self.defense_stage = None
        else:
            self.event_name = ''
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team} - {self.stage_label} on {self.scheduled_date}'


class SchedulePanelist(models.Model):
    schedule = models.ForeignKey(
        DefenseSchedule,
        related_name='panel_assignments',
        on_delete=models.CASCADE,
    )
    panelist = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='schedule_panel_assignments',
        on_delete=models.CASCADE,
    )
    order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_scheduler_schedulepanelist'
        ordering = ['order', 'panelist__username']
        constraints = [
            models.UniqueConstraint(fields=['schedule', 'panelist'], name='unique_panelist_per_schedule'),
        ]

    def clean(self):
        if self.panelist_id:
            is_faculty = getattr(self.panelist, 'role', None) in ['faculty', 'admin']
            if not is_faculty or not getattr(self.panelist, 'is_panelist', False):
                raise ValidationError({'panelist': 'Schedule panelists must be assigned faculty panelists.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.panelist} -> {self.schedule}'


class PitEventGradingConfig(models.Model):
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='pit_event_grading_configs',
        on_delete=models.CASCADE,
    )
    event_name = models.CharField(max_length=120)
    panel_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='pit_event_configs_as_panel',
        on_delete=models.PROTECT,
    )
    peer_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='pit_event_configs_as_peer',
        on_delete=models.PROTECT,
    )
    panel_weight = models.PositiveSmallIntegerField(default=80)
    peer_weight = models.PositiveSmallIntegerField(default=20)
    is_officially_complete = models.BooleanField(default=False)
    peer_grading_enabled = models.BooleanField(default=False)
    vault_file_template = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Template for vault filename. Variables: {year}, {course}, {project}, {event}, {semester}',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_scheduler_piteventgradingconfig'
        constraints = [
            models.UniqueConstraint(
                fields=['semester', 'event_name'],
                name='unique_pit_event_config_per_semester',
            ),
        ]
        ordering = ['event_name']

    def clean(self):
        errors = {}
        if self.panel_weight + self.peer_weight != 100:
            errors['panel_weight'] = 'Panel and peer weights must total 100%.'
        from grading.rubrics.models import Rubric

        if self.panel_rubric_id:
            rubric = self.panel_rubric
            if rubric.evaluation_type != Rubric.EVAL_PANEL or rubric.scope != Rubric.SCOPE_PIT:
                errors['panel_rubric'] = 'Panel rubric must be a PIT panel rubric.'
        if self.peer_rubric_id:
            rubric = self.peer_rubric
            if rubric.evaluation_type != Rubric.EVAL_PEER or rubric.scope != Rubric.SCOPE_PIT:
                errors['peer_rubric'] = 'Peer rubric must be a PIT peer rubric.'
        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        self.event_name = (self.event_name or '').strip()
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.event_name} ({self.semester})'
