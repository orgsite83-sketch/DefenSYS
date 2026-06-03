from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class StudentTeam(models.Model):
    LEVEL_1_PIT = '1st Year PIT'
    LEVEL_2_PIT = '2nd Year PIT'
    LEVEL_3_PIT = '3rd Year PIT'
    LEVEL_3_CAPSTONE = '3rd Year Capstone'
    LEVEL_4_CAPSTONE = '4th Year Capstone'

    LEVEL_CHOICES = (
        (LEVEL_1_PIT, LEVEL_1_PIT),
        (LEVEL_2_PIT, LEVEL_2_PIT),
        (LEVEL_3_PIT, LEVEL_3_PIT),
        (LEVEL_3_CAPSTONE, LEVEL_3_CAPSTONE),
        (LEVEL_4_CAPSTONE, LEVEL_4_CAPSTONE),
    )

    STATUS_PENDING = 'Pending'
    STATUS_APPROVED = 'Approved'
    STATUS_FAILED = 'Failed'
    STATUS_DELAYED = 'Delayed/Extended'

    STATUS_CHOICES = (
        (STATUS_PENDING, STATUS_PENDING),
        (STATUS_APPROVED, STATUS_APPROVED),
        (STATUS_FAILED, STATUS_FAILED),
        (STATUS_DELAYED, STATUS_DELAYED),
    )

    PHASE_ACTIVE = 'active'
    PHASE_EXTENDED = 'extended'

    PHASE_CHOICES = (
        (PHASE_ACTIVE, PHASE_ACTIVE),
        (PHASE_EXTENDED, PHASE_EXTENDED),
    )

    name = models.CharField(max_length=120)
    project_title = models.CharField(max_length=255)
    level = models.CharField(max_length=30, choices=LEVEL_CHOICES)
    year_level = models.CharField(max_length=20)
    section = models.CharField(max_length=80, blank=True, default='')
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='teams',
        on_delete=models.PROTECT,
    )
    leader = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='led_teams',
        on_delete=models.PROTECT,
    )
    adviser = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='advised_student_teams',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    members = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        related_name='student_teams',
        through='TeamMembership',
    )
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default=STATUS_PENDING)
    capstone_phase = models.CharField(max_length=20, choices=PHASE_CHOICES, null=True, blank=True)
    ready_for_stage = models.CharField(max_length=80, null=True, blank=True)
    current_defense_stage = models.CharField(max_length=80, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']
        constraints = [
            models.UniqueConstraint(fields=['name', 'level'], name='unique_team_name_per_level'),
        ]

    @property
    def is_capstone(self):
        return 'Capstone' in self.level

    @property
    def is_pit(self):
        return 'PIT' in self.level

    def clean(self):
        if self.leader_id and getattr(self.leader, 'role', None) != 'student':
            raise ValidationError({'leader': 'Team leader must be a student.'})
        if self.adviser_id and getattr(self.adviser, 'role', None) not in ['faculty', 'admin']:
            raise ValidationError({'adviser': 'Adviser must be a faculty or admin user.'})

    def save(self, *args, **kwargs):
        if not self.project_title:
            self.project_title = self.name
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.name} ({self.level})'


class TeamMembership(models.Model):
    team = models.ForeignKey(StudentTeam, related_name='memberships', on_delete=models.CASCADE)
    student = models.ForeignKey(settings.AUTH_USER_MODEL, related_name='team_memberships', on_delete=models.CASCADE)
    is_leader = models.BooleanField(default=False)
    order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['order', 'student__username']
        constraints = [
            models.UniqueConstraint(fields=['team', 'student'], name='unique_student_per_team'),
        ]

    def clean(self):
        if self.student_id and getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Team members must be student users.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.student} -> {self.team}'


class TeamStageProgress(models.Model):
    STATUS_LOCKED = 'locked'
    STATUS_READY = 'ready'
    STATUS_SCHEDULED = 'scheduled'
    STATUS_GRADING = 'grading'
    STATUS_PASSED = 'passed'
    STATUS_FAILED = 'failed'
    STATUS_ARCHIVED = 'archived'

    STATUS_CHOICES = (
        (STATUS_LOCKED, 'Locked'),
        (STATUS_READY, 'Ready'),
        (STATUS_SCHEDULED, 'Scheduled'),
        (STATUS_GRADING, 'Grading'),
        (STATUS_PASSED, 'Passed'),
        (STATUS_FAILED, 'Failed'),
        (STATUS_ARCHIVED, 'Archived'),
    )

    team = models.ForeignKey(
        StudentTeam,
        related_name='stage_progress',
        on_delete=models.CASCADE,
    )
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='team_stage_progress',
        on_delete=models.PROTECT,
    )
    defense_stage = models.ForeignKey(
        'defense.DefenseStage',
        related_name='team_progress',
        on_delete=models.PROTECT,
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_LOCKED)
    grade = models.ForeignKey(
        'grading.TeamGrade',
        related_name='stage_progress_records',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    ready_at = models.DateTimeField(null=True, blank=True)
    scheduled_at = models.DateTimeField(null=True, blank=True)
    graded_at = models.DateTimeField(null=True, blank=True)
    archived_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='created_team_stage_progress',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='updated_team_stage_progress',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['team__name', 'defense_stage__display_order', 'defense_stage__label']
        constraints = [
            models.UniqueConstraint(
                fields=['team', 'semester', 'defense_stage'],
                name='unique_team_stage_progress',
            ),
        ]
        indexes = [
            models.Index(fields=['semester', 'defense_stage', 'status'], name='team_stage_progress_idx'),
        ]

    def __str__(self):
        return f'{self.team} - {self.defense_stage}: {self.status}'


class TeamAdviserAssignment(models.Model):
    """Audit trail when a team's capstone adviser is assigned or changed."""

    team = models.ForeignKey(
        StudentTeam,
        related_name='adviser_assignments',
        on_delete=models.CASCADE,
    )
    adviser = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='team_adviser_assignments',
    )
    assigned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='adviser_assignments_made',
    )
    assigned_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    reason = models.CharField(max_length=255, blank=True, default='')

    class Meta:
        ordering = ['-assigned_at', '-id']

    def __str__(self):
        adviser_label = self.adviser.username if self.adviser_id else 'Unassigned'
        return f'{self.team.name}: {adviser_label}'


from student_teams.documents.models import TeamDocument  # noqa: E402,F401
from student_teams.weekly_progress.models import WeeklyProgressReport  # noqa: E402,F401
