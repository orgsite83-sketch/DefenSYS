from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class TeamGrade(models.Model):
    SCOPE_CAPSTONE = 'capstone'
    SCOPE_PIT = 'pit'

    SCOPE_CHOICES = (
        (SCOPE_CAPSTONE, 'Capstone'),
        (SCOPE_PIT, 'PIT'),
    )

    STATUS_PENDING = 'pending'
    STATUS_AWAITING_PEERS = 'awaiting_peers'
    STATUS_PUBLISHED = 'published'

    STATUS_CHOICES = (
        (STATUS_PENDING, 'Pending'),
        (STATUS_AWAITING_PEERS, 'Awaiting Peers'),
        (STATUS_PUBLISHED, 'Published'),
    )

    schedule = models.ForeignKey(
        'defense_scheduler.DefenseSchedule',
        related_name='grade_records',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    team = models.ForeignKey(
        'student_teams.StudentTeam',
        related_name='grade_records',
        on_delete=models.CASCADE,
    )
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='grade_records',
        on_delete=models.PROTECT,
    )
    scope = models.CharField(max_length=20, choices=SCOPE_CHOICES, default=SCOPE_CAPSTONE)
    stage_label = models.CharField(max_length=120, default='Unscheduled')
    panel_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    adviser_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    peer_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    final_grade = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    panel_weight = models.PositiveSmallIntegerField(default=50)
    adviser_weight = models.PositiveSmallIntegerField(default=30)
    peer_weight = models.PositiveSmallIntegerField(default=20)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    published_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='published_grade_records',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    published_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['team__level', 'team__name', 'stage_label']
        constraints = [
            models.UniqueConstraint(
                fields=['team', 'semester', 'scope', 'stage_label'],
                name='unique_grade_record_per_team_context',
            ),
        ]
        indexes = [
            models.Index(fields=['scope', 'status']),
            models.Index(fields=['stage_label']),
        ]

    @property
    def is_capstone(self):
        return self.scope == self.SCOPE_CAPSTONE

    @property
    def is_complete(self):
        return all(getattr(self, field) is not None for field in self.required_score_fields)

    @property
    def required_score_fields(self):
        fields = ['panel_score', 'peer_score']
        if self.is_capstone and self.adviser_weight > 0:
            fields.append('adviser_score')
        return fields

    @property
    def result(self):
        if self.final_grade is None:
            return 'pending'
        return 'passed' if self.final_grade >= Decimal('75.00') else 'failed'

    def clean(self):
        errors = {}
        for field in ['panel_score', 'adviser_score', 'peer_score', 'final_grade']:
            value = getattr(self, field)
            if value is not None and (value < 0 or value > 100):
                errors[field] = 'Score must be between 0 and 100.'

        weight_total = self.panel_weight + self.adviser_weight + self.peer_weight
        if weight_total != 100:
            errors['weights'] = 'Panel, adviser, and peer weights must total 100%.'
        if self.scope == self.SCOPE_PIT and self.adviser_weight != 0:
            errors['adviser_weight'] = 'PIT adviser weight must be 0%.'
        if self.status == self.STATUS_PUBLISHED and not self.is_complete:
            errors['status'] = 'Only complete grades can be published.'

        if errors:
            raise ValidationError(errors)

    def recalculate(self, keep_published=False):
        if self.is_complete:
            total = (
                self.panel_score * Decimal(self.panel_weight)
                + self.peer_score * Decimal(self.peer_weight)
            )
            if self.is_capstone and self.adviser_weight > 0:
                total += self.adviser_score * Decimal(self.adviser_weight)
            self.final_grade = (total / Decimal('100')).quantize(Decimal('0.01'))
            if self.status != self.STATUS_PUBLISHED:
                self.status = self.STATUS_PENDING
            return

        self.final_grade = None
        if self.status == self.STATUS_PUBLISHED:
            self.status = self.STATUS_PENDING

        has_panel = self.panel_score is not None
        has_adviser = (not self.is_capstone or self.adviser_weight == 0 or self.adviser_score is not None)
        if has_panel and has_adviser and self.peer_score is None:
            self.status = self.STATUS_AWAITING_PEERS
        else:
            self.status = self.STATUS_PENDING

    def publish(self, user=None):
        self.recalculate()
        if not self.is_complete:
            raise ValidationError({'status': 'Only complete grades can be published.'})
        self.status = self.STATUS_PUBLISHED
        self.published_by = user
        self.published_at = timezone.now()
        self.save()

    def save(self, *args, **kwargs):
        if self.scope == self.SCOPE_PIT:
            self.adviser_weight = 0
        self.recalculate(keep_published=True)
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team} - {self.stage_label}'


class GradeBreakdown(models.Model):
    EVAL_PANEL = 'panel'
    EVAL_ADVISER = 'adviser'
    EVAL_PEER = 'peer'

    EVALUATION_TYPE_CHOICES = (
        (EVAL_PANEL, 'Panel'),
        (EVAL_ADVISER, 'Adviser'),
        (EVAL_PEER, 'Peer'),
    )

    team_grade = models.ForeignKey(TeamGrade, related_name='breakdowns', on_delete=models.CASCADE)
    rubric = models.ForeignKey(
        'rubric_engine.Rubric',
        related_name='grade_breakdowns',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    evaluation_type = models.CharField(max_length=20, choices=EVALUATION_TYPE_CHOICES)
    criterion_name = models.CharField(max_length=160)
    score = models.DecimalField(max_digits=7, decimal_places=2)
    max_score = models.DecimalField(max_digits=7, decimal_places=2)
    remarks = models.TextField(blank=True)
    display_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['evaluation_type', 'display_order', 'id']
        indexes = [
            models.Index(fields=['evaluation_type']),
        ]

    @property
    def normalized_score(self):
        if self.max_score <= 0:
            return Decimal('0.00')
        return (self.score / self.max_score * Decimal('100')).quantize(Decimal('0.01'))

    def clean(self):
        if self.max_score <= 0:
            raise ValidationError({'max_score': 'Max score must be greater than 0.'})
        if self.score < 0 or self.score > self.max_score:
            raise ValidationError({'score': 'Score must be between 0 and max score.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team_grade} - {self.criterion_name}'


class StudentPeerGrade(models.Model):
    team_grade = models.ForeignKey(TeamGrade, related_name='peer_member_grades', on_delete=models.CASCADE)
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='received_peer_grade_summaries',
        on_delete=models.CASCADE,
    )
    average_score = models.DecimalField(max_digits=6, decimal_places=2)
    max_score = models.DecimalField(max_digits=6, decimal_places=2, default=5)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['student__last_name', 'student__first_name', 'student__username']
        constraints = [
            models.UniqueConstraint(
                fields=['team_grade', 'student'],
                name='unique_peer_grade_per_student_grade_context',
            ),
        ]

    @property
    def normalized_score(self):
        if self.max_score <= 0:
            return Decimal('0.00')
        return (self.average_score / self.max_score * Decimal('100')).quantize(Decimal('0.01'))

    def clean(self):
        if getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Peer grade summaries must point to student users.'})
        if self.max_score <= 0:
            raise ValidationError({'max_score': 'Max score must be greater than 0.'})
        if self.average_score < 0 or self.average_score > self.max_score:
            raise ValidationError({'average_score': 'Average score must be between 0 and max score.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.student} peer score for {self.team_grade}'
