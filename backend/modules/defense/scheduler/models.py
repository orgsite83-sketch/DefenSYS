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
    documenter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='documenter_defense_schedules',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        help_text='Faculty assigned as documenter for this capstone defense.',
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

        if self.documenter_id:
            if self.scope == self.SCOPE_PIT:
                errors['documenter'] = 'PIT schedules cannot have a documenter.'
            else:
                role = getattr(self.documenter, 'role', None)
                if role not in ['faculty', 'admin']:
                    errors['documenter'] = 'Documenter must be a faculty or admin user.'

                if self.team_id and self.team.adviser_id == self.documenter_id:
                    errors['documenter'] = "Documenter cannot be the team's adviser."

                if self.pk and self.panelists.filter(pk=self.documenter_id).exists():
                    errors['documenter'] = 'Documenter cannot be one of the panelists assigned to this schedule.'

        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        old_status = None
        if not is_new:
            try:
                old_status = DefenseSchedule.objects.filter(pk=self.pk).values_list('status', flat=True).first()
            except Exception:
                pass

        if self.scope == self.SCOPE_PIT:
            self.defense_stage = None
        else:
            self.event_name = ''
        self.full_clean()
        super().save(*args, **kwargs)

        # Sync TeamStageProgress status for Capstone schedules
        if self.scope == self.SCOPE_CAPSTONE and self.defense_stage:
            from student_teams.models import StudentTeam, TeamStageProgress
            if StudentTeam.objects.filter(pk=self.team.pk).exists():
                if self.status == self.STATUS_SCHEDULED:
                    from student_teams.services import mark_stage_scheduled
                    mark_stage_scheduled(self.team, self.defense_stage, user=self.created_by)
                elif old_status == self.STATUS_SCHEDULED and self.status in [self.STATUS_CANCELLED, self.STATUS_ARCHIVED]:
                    # Revert to ready if no other active/scheduled schedules exist
                    progress = TeamStageProgress.objects.filter(
                        team=self.team,
                        semester=self.semester,
                        defense_stage=self.defense_stage
                    ).first()
                    if progress and progress.status == TeamStageProgress.STATUS_SCHEDULED:
                        has_other = DefenseSchedule.objects.filter(
                            scope=self.SCOPE_CAPSTONE,
                            team=self.team,
                            defense_stage=self.defense_stage,
                            status__in=[self.STATUS_SCHEDULED, self.STATUS_DONE]
                        ).exclude(pk=self.pk).exists()
                        if not has_other:
                            from student_teams.services import mark_stage_ready
                            mark_stage_ready(self.team, self.defense_stage)

    def delete(self, *args, **kwargs):
        team = self.team
        stage = self.defense_stage
        scope = self.scope
        semester = self.semester
        status = self.status
        pk = self.pk

        result = super().delete(*args, **kwargs)

        if scope == self.SCOPE_CAPSTONE and stage:
            from student_teams.models import StudentTeam, TeamStageProgress
            if StudentTeam.objects.filter(pk=team.pk).exists():
                progress = TeamStageProgress.objects.filter(
                    team=team,
                    semester=semester,
                    defense_stage=stage
                ).first()
                if progress and progress.status == TeamStageProgress.STATUS_SCHEDULED:
                    has_other = DefenseSchedule.objects.filter(
                        scope=self.SCOPE_CAPSTONE,
                        team=team,
                        defense_stage=stage,
                        status__in=[self.STATUS_SCHEDULED, self.STATUS_DONE]
                    ).exclude(pk=pk).exists()
                    if not has_other:
                        from student_teams.services import mark_stage_ready
                        mark_stage_ready(team, stage)
        return result

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
    is_chair = models.BooleanField(default=False)
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
            if not is_faculty:
                raise ValidationError({'panelist': 'Schedule panelists must be assigned faculty or admin users.'})
            if self.schedule_id and self.panelist_id == self.schedule.documenter_id:
                raise ValidationError({'panelist': 'A panelist cannot be assigned as the documenter for this schedule.'})

        if self.is_chair and self.schedule_id:
            qs = SchedulePanelist.objects.filter(schedule=self.schedule, is_chair=True)
            if self.pk:
                qs = qs.exclude(pk=self.pk)
            if qs.exists():
                raise ValidationError({'is_chair': 'At most one panelist per schedule can be marked as chair.'})

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
    event_code = models.SlugField(max_length=140, blank=True, default='')
    panel_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='pit_event_configs_as_panel',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    peer_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='pit_event_configs_as_peer',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    panel_weight = models.PositiveSmallIntegerField(default=80)
    peer_weight = models.PositiveSmallIntegerField(default=20)
    is_officially_complete = models.BooleanField(default=False)
    peer_grading_enabled = models.BooleanField(default=False)
    archive_file_template = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Template for archive filename. Variables: {year}, {course}, {project}, {event}, {semester}',
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
        if self.pk:
            old = PitEventGradingConfig.objects.filter(pk=self.pk).values('event_name', 'event_code').first()
            if old:
                from django.utils.text import slugify
                old_name_slug = slugify(old['event_name'])
                old_code = old.get('event_code') or ''
                if not self.event_code or self.event_code.lower() == old_name_slug:
                    self.event_code = unique_pit_event_code(self.event_name, semester=self.semester, instance_id=self.pk, is_custom=False)
                else:
                    is_custom = self.event_code.lower() != old_code.lower() or self.event_code.lower() != old_name_slug
                    self.event_code = unique_pit_event_code(self.event_code, semester=self.semester, instance_id=self.pk, is_custom=is_custom)
            else:
                self.event_code = unique_pit_event_code(self.event_code or self.event_name, semester=self.semester, instance_id=self.pk, is_custom=bool(self.event_code))
        else:
            self.event_code = unique_pit_event_code(self.event_code or self.event_name, semester=self.semester, instance_id=self.pk, is_custom=bool(self.event_code))
        self.full_clean()
        super().save(*args, **kwargs)
        from grading.grades.models import TeamGrade
        from django.db.models import Q

        TeamGrade.objects.filter(
            Q(pit_event_config=self) | Q(semester=self.semester, scope=TeamGrade.SCOPE_PIT, stage_label__iexact=self.event_name),
            status=TeamGrade.STATUS_PENDING,
        ).update(
            pit_event_config=self,
            panel_weight=self.panel_weight,
            peer_weight=self.peer_weight,
        )

    def __str__(self):
        return f'{self.event_name} ({self.semester})'


def unique_pit_event_code(raw_value_or_name, semester=None, instance_id=None, is_custom=False):
    from defense.stages.models import clean_custom_code
    from django.utils.text import slugify

    if is_custom and raw_value_or_name and raw_value_or_name.strip():
        base_code = clean_custom_code(raw_value_or_name) or 'event'
    else:
        base_code = slugify(raw_value_or_name) or 'event'

    code = base_code
    index = 2
    queryset = PitEventGradingConfig.objects.filter(event_code__iexact=code)
    if semester:
        queryset = queryset.filter(semester=semester)
    if instance_id is not None:
        queryset = queryset.exclude(pk=instance_id)

    while queryset.exists():
        code = f'{base_code}-{index}'
        queryset = PitEventGradingConfig.objects.filter(event_code__iexact=code)
        if semester:
            queryset = queryset.filter(semester=semester)
        if instance_id is not None:
            queryset = queryset.exclude(pk=instance_id)
        index += 1

    return code


class PitEventDeliverable(models.Model):
    TYPE_PRE = 'pre'
    TYPE_POST = 'post'

    TYPE_CHOICES = (
        (TYPE_PRE, 'Pre-Defense'),
        (TYPE_POST, 'Post-Defense'),
    )

    pit_event_config = models.ForeignKey(
        PitEventGradingConfig,
        related_name='deliverables',
        on_delete=models.CASCADE,
    )
    deliverable_id = models.CharField(max_length=20)
    label = models.CharField(max_length=180)
    deliverable_type = models.CharField(
        max_length=20,
        choices=TYPE_CHOICES,
        default=TYPE_PRE,
    )
    required = models.BooleanField(default=True)
    display_order = models.PositiveSmallIntegerField(default=1)
    archive_note = models.TextField(blank=True)
    archive_file_template = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Template for archive filename. Variables: {year}, {course}, {project}, {event}, {semester}',
    )
    is_restricted = models.BooleanField(
        default=False,
        help_text='If checked, this post-defense deliverable will be hidden from the public Project Repository.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_scheduler_piteventdeliverable'
        ordering = ['display_order', 'deliverable_id']
        constraints = [
            models.UniqueConstraint(
                fields=['pit_event_config', 'deliverable_id'],
                name='unique_deliverable_per_pit_event',
            ),
        ]

    def __str__(self):
        return f'{self.pit_event_config.event_name} - {self.label}'
