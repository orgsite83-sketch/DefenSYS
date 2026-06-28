from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import Q
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

    LOCKED_STATUSES = frozenset({STATUS_PUBLISHED})

    schedule = models.ForeignKey(
        'defense.DefenseSchedule',
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
    defense_stage = models.ForeignKey(
        'defense.DefenseStage',
        related_name='grade_records',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
    pit_event_config = models.ForeignKey(
        'defense.PitEventGradingConfig',
        related_name='grade_records',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
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
        app_label = 'grading'
        db_table = 'grade_center_teamgrade'
        ordering = ['team__level', 'team__name', 'stage_label']
        constraints = [
            models.UniqueConstraint(
                fields=['team', 'semester', 'scope', 'defense_stage'],
                condition=Q(scope='capstone', defense_stage__isnull=False),
                name='unique_capstone_grade_per_team_stage',
            ),
            models.UniqueConstraint(
                fields=['team', 'semester', 'scope', 'pit_event_config'],
                condition=Q(scope='pit', pit_event_config__isnull=False),
                name='unique_pit_grade_per_team_event',
            ),
        ]
        indexes = [
            models.Index(fields=['scope', 'status'], name='grade_cente_scope_8e8f63_idx'),
            models.Index(fields=['stage_label'], name='grade_cente_stage_l_1fb308_idx'),
            models.Index(fields=['defense_stage'], name='grade_cente_def_sta_idx'),
            models.Index(fields=['pit_event_config'], name='grade_cente_pit_evt_idx'),
        ]

    @property
    def is_capstone(self):
        return self.scope == self.SCOPE_CAPSTONE

    @property
    def is_complete(self):
        is_student_specific = False
        if self.schedule and self.schedule.rubric:
            is_student_specific = (self.schedule.rubric.target_type in ('individual', 'both'))
        elif self.pit_event_config and self.pit_event_config.panel_rubric:
            is_student_specific = (self.pit_event_config.panel_rubric.target_type in ('individual', 'both'))

        if is_student_specific:
            if not self.pk:
                return False
            memberships = self.team.memberships.all()
            if not memberships.exists():
                return False
            sg_by_student = {sg.student_id: sg for sg in self.student_grades.all()}
            for membership in memberships:
                sg = sg_by_student.get(membership.student_id)
                if not sg or sg.panel_score is None:
                    return False

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

        if self.scope == self.SCOPE_PIT:
            if self.panel_weight + self.peer_weight != 100:
                errors['weights'] = 'Panel and peer weights must total 100%.'
        elif self.panel_weight + self.adviser_weight + self.peer_weight != 100:
            errors['weights'] = 'Panel, adviser, and peer weights must total 100%.'
        if self.status in self.LOCKED_STATUSES and not self.is_complete:
            errors['status'] = 'Only complete grades can be locked or published.'

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
            if self.status not in self.LOCKED_STATUSES:
                self.status = self.STATUS_PENDING
            return

        self.final_grade = None
        if self.status in self.LOCKED_STATUSES:
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
            self.defense_stage = None
            if self.pit_event_config_id:
                self.stage_label = self.pit_event_config.event_name
        else:
            self.pit_event_config = None
            if self.defense_stage_id:
                self.stage_label = self.defense_stage.label
        self.recalculate(keep_published=True)
        self.full_clean()
        super().save(*args, **kwargs)

        try:
            from .peer_eval import recalculate_student_grade
            memberships = list(self.team.memberships.select_related('student').all())
            for membership in memberships:
                sg, _ = StudentStageGrade.objects.get_or_create(team_grade=self, student=membership.student)
                sg.adviser_score = self.adviser_score
                is_student_specific = False
                if self.schedule and self.schedule.rubric:
                    is_student_specific = (self.schedule.rubric.target_type in ('individual', 'both'))
                elif self.pit_event_config and self.pit_event_config.panel_rubric:
                    is_student_specific = (self.pit_event_config.panel_rubric.target_type in ('individual', 'both'))
                if not is_student_specific:
                    sg.panel_score = self.panel_score
                sg.save()
                recalculate_student_grade(sg)
        except Exception:
            pass

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
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name='grade_breakdowns',
    )
    rubric = models.ForeignKey(
        'grading.Rubric',
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
        app_label = 'grading'
        db_table = 'grade_center_gradebreakdown'
        ordering = ['evaluation_type', 'display_order', 'id']
        indexes = [
            models.Index(fields=['evaluation_type'], name='grade_cente_evaluat_389856_idx'),
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


class PanelistGradeSubmission(models.Model):
    team_grade = models.ForeignKey(
        TeamGrade,
        related_name='panelist_submissions',
        on_delete=models.CASCADE,
    )
    schedule = models.ForeignKey(
        'defense.DefenseSchedule',
        related_name='panelist_grade_submissions',
        on_delete=models.CASCADE,
    )
    panelist = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='panelist_grade_submissions',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name='panelist_student_submissions',
    )
    guest_code_id = models.CharField(max_length=64, null=True, blank=True)
    guest_code = models.CharField(max_length=64, blank=True)
    guest_name = models.CharField(max_length=160, blank=True)
    remarks = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'grade_center_panelistgradesubmission'
        ordering = ['-updated_at', '-id']
        constraints = [
            models.UniqueConstraint(
                fields=['team_grade', 'schedule', 'panelist'],
                condition=Q(panelist__isnull=False, student__isnull=True),
                name='unique_panel_submission_per_panelist',
            ),
            models.UniqueConstraint(
                fields=['team_grade', 'schedule', 'panelist', 'student'],
                condition=Q(panelist__isnull=False, student__isnull=False),
                name='unique_panel_submission_per_panelist_student',
            ),
            models.UniqueConstraint(
                fields=['team_grade', 'schedule', 'guest_code_id'],
                condition=Q(guest_code_id__isnull=False, student__isnull=True),
                name='unique_panel_submission_per_guest',
            ),
            models.UniqueConstraint(
                fields=['team_grade', 'schedule', 'guest_code_id', 'student'],
                condition=Q(guest_code_id__isnull=False, student__isnull=False),
                name='unique_panel_submission_per_guest_student',
            ),
        ]
        indexes = [
            models.Index(fields=['team_grade', 'schedule'], name='grade_cente_panel__ctx_idx'),
            models.Index(fields=['guest_code_id'], name='grade_cente_guest_c_idx'),
        ]

    @property
    def identity_label(self):
        if self.panelist_id:
            return f'Panelist: {self.panelist.username}'
        return f'Guest panelist: {self.guest_name} ({self.guest_code})'

    def clean(self):
        if bool(self.panelist_id) == bool(self.guest_code_id):
            raise ValidationError({'panelist': 'Use either a panelist or a guest identity.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.identity_label} - {self.team_grade}'


class PanelistCriterionScore(models.Model):
    submission = models.ForeignKey(
        PanelistGradeSubmission,
        related_name='criterion_scores',
        on_delete=models.CASCADE,
    )
    criterion = models.ForeignKey(
        'grading.RubricCriterion',
        related_name='panelist_scores',
        on_delete=models.PROTECT,
    )
    criterion_name_snapshot = models.CharField(max_length=160)
    score = models.DecimalField(max_digits=7, decimal_places=2)
    max_score_snapshot = models.DecimalField(max_digits=7, decimal_places=2)
    display_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'grade_center_panelistcriterionscore'
        ordering = ['display_order', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['submission', 'criterion'],
                name='unique_panel_score_per_criterion',
            ),
        ]
        indexes = [
            models.Index(fields=['criterion'], name='grade_cente_crit_id_idx'),
        ]

    @property
    def normalized_score(self):
        if self.max_score_snapshot <= 0:
            return Decimal('0.00')
        return (self.score / self.max_score_snapshot * Decimal('100')).quantize(Decimal('0.01'))

    def clean(self):
        if self.max_score_snapshot <= 0:
            raise ValidationError({'max_score_snapshot': 'Max score must be greater than 0.'})
        if self.score < 0 or self.score > self.max_score_snapshot:
            raise ValidationError({'score': 'Score must be between 0 and max score.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.submission} - {self.criterion_name_snapshot}'


class StudentStageGrade(models.Model):
    team_grade = models.ForeignKey(TeamGrade, related_name='student_grades', on_delete=models.CASCADE)
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='received_stage_grade_summaries',
        on_delete=models.CASCADE,
    )
    panel_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    adviser_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    peer_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    final_grade = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'grade_center_studentstagegrade'
        ordering = ['student__last_name', 'student__first_name', 'student__username']
        constraints = [
            models.UniqueConstraint(
                fields=['team_grade', 'student'],
                name='unique_student_stage_grade',
            ),
        ]

    def clean(self):
        if getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Stage grade summaries must point to student users.'})
        for field in ['panel_score', 'adviser_score', 'peer_score', 'final_grade']:
            value = getattr(self, field)
            if value is not None and (value < 0 or value > 100):
                raise ValidationError({field: 'Score must be between 0 and 100.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.student} grade summary for {self.team_grade}'


class PeerEvaluationSubmission(models.Model):
    team_grade = models.ForeignKey(
        TeamGrade,
        related_name='peer_evaluation_submissions',
        on_delete=models.CASCADE,
    )
    evaluator = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='peer_evaluations_given',
        on_delete=models.CASCADE,
    )
    evaluatee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='peer_evaluations_received',
        on_delete=models.CASCADE,
    )
    total_score = models.DecimalField(max_digits=7, decimal_places=2)
    max_score = models.DecimalField(max_digits=7, decimal_places=2)
    breakdown = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'grade_center_peerevaluationsubmission'
        ordering = ['-updated_at', '-id']
        constraints = [
            models.UniqueConstraint(
                fields=['team_grade', 'evaluator', 'evaluatee'],
                name='unique_peer_submission_per_evaluator_evaluatee',
            ),
        ]

    def __str__(self):
        return f'{self.evaluator} → {self.evaluatee} ({self.team_grade})'
