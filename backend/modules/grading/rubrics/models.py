from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class Rubric(models.Model):
    SCOPE_CAPSTONE = 'capstone'
    SCOPE_PIT = 'pit'

    SCOPE_CHOICES = (
        (SCOPE_CAPSTONE, 'Capstone'),
        (SCOPE_PIT, 'PIT'),
    )

    EVAL_PANEL = 'panel'
    EVAL_ADVISER = 'adviser'
    EVAL_PEER = 'peer'

    EVALUATION_TYPE_CHOICES = (
        (EVAL_PANEL, 'Panel'),
        (EVAL_ADVISER, 'Adviser'),
        (EVAL_PEER, 'Peer'),
    )

    SCALE_5 = '5-Point Scale'
    SCALE_10 = '10-Point Scale'
    SCALE_100 = '100-Point Scale'

    SCALE_CHOICES = (
        (SCALE_5, SCALE_5),
        (SCALE_10, SCALE_10),
        (SCALE_100, SCALE_100),
    )

    STATUS_DRAFT = 'draft'
    STATUS_PUBLISHED = 'published'

    STATUS_CHOICES = (
        (STATUS_DRAFT, 'Draft'),
        (STATUS_PUBLISHED, 'Published'),
    )

    TARGET_TEAM = 'team'
    TARGET_INDIVIDUAL = 'individual'
    TARGET_BOTH = 'both'

    TARGET_CHOICES = (
        (TARGET_TEAM, 'Team'),
        (TARGET_INDIVIDUAL, 'Individual'),
        (TARGET_BOTH, 'Both (Team & Individual)'),
    )

    name = models.CharField(max_length=160)
    scope = models.CharField(max_length=20, choices=SCOPE_CHOICES, default=SCOPE_CAPSTONE)
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='rubrics',
        on_delete=models.PROTECT,
    )
    defense_stage = models.ForeignKey(
        'defense.DefenseStage',
        related_name='rubrics',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
    event_name = models.CharField(max_length=120, blank=True)
    evaluation_type = models.CharField(max_length=20, choices=EVALUATION_TYPE_CHOICES)
    target_type = models.CharField(max_length=20, choices=TARGET_CHOICES, default=TARGET_TEAM)
    scale = models.CharField(max_length=30, choices=SCALE_CHOICES, default=SCALE_10)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT)
    is_locked = models.BooleanField(default=False)
    panel_weight = models.PositiveSmallIntegerField(default=50)
    adviser_weight = models.PositiveSmallIntegerField(default=30)
    peer_weight = models.PositiveSmallIntegerField(default=20)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='created_rubrics',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'rubric_engine_rubric'
        ordering = ['-updated_at', 'name']
        indexes = [
            models.Index(fields=['scope', 'status'], name='rubric_engi_scope_11d033_idx'),
            models.Index(fields=['evaluation_type'], name='rubric_engi_evaluat_c19eb7_idx'),
        ]

    @property
    def context_label(self):
        if self.scope == self.SCOPE_PIT:
            return 'PIT'
        return self.defense_stage.label if self.defense_stage else 'All Stages'

    @property
    def criteria_count(self):
        return self.criteria.count()

    def clean(self):
        if self.evaluation_type == self.EVAL_PEER:
            self.target_type = self.TARGET_INDIVIDUAL

        errors = {}
        if self.scope == self.SCOPE_PIT:
            if self.evaluation_type == self.EVAL_ADVISER:
                errors['evaluation_type'] = 'PIT rubrics do not support adviser evaluation.'
        elif self.panel_weight + self.adviser_weight + self.peer_weight != 100:
            errors['weights'] = 'Panel, adviser, and peer weights must total 100%.'

        for field in ['panel_weight', 'adviser_weight', 'peer_weight']:
            value = getattr(self, field)
            if value > 100:
                errors[field] = 'Weight cannot be greater than 100%.'

        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        if self.scope == self.SCOPE_PIT:
            self.defense_stage = None
            self.adviser_weight = 0
            self.panel_weight = 0
            self.peer_weight = 0
            self.event_name = ''
        else:
            self.event_name = ''
        if self.status == self.STATUS_PUBLISHED:
            self.is_locked = True
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.name} ({self.get_evaluation_type_display()})'


class RubricCriterion(models.Model):
    rubric = models.ForeignKey(Rubric, related_name='criteria', on_delete=models.CASCADE)
    name = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    scale = models.CharField(max_length=30, choices=Rubric.SCALE_CHOICES, default=Rubric.SCALE_10)
    max_score = models.PositiveSmallIntegerField(default=10)
    weight = models.DecimalField(max_digits=5, decimal_places=2, default=1)
    display_order = models.PositiveSmallIntegerField(default=0)
    target_type = models.CharField(
        max_length=20,
        choices=(
            (Rubric.TARGET_TEAM, 'Team'),
            (Rubric.TARGET_INDIVIDUAL, 'Individual'),
        ),
        default=Rubric.TARGET_TEAM,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'grading'
        db_table = 'rubric_engine_rubriccriterion'
        ordering = ['display_order', 'id']

    def clean(self):
        if self.max_score < 1:
            raise ValidationError({'max_score': 'Max score must be at least 1.'})
        if self.weight <= 0:
            raise ValidationError({'weight': 'Criterion weight must be greater than 0.'})
        if self.rubric.target_type == Rubric.TARGET_TEAM and self.target_type != Rubric.TARGET_TEAM:
            self.target_type = Rubric.TARGET_TEAM
        elif self.rubric.target_type == Rubric.TARGET_INDIVIDUAL and self.target_type != Rubric.TARGET_INDIVIDUAL:
            self.target_type = Rubric.TARGET_INDIVIDUAL

    def save(self, *args, **kwargs):
        if not self.max_score:
            self.max_score = default_max_score(self.scale)
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.name} - {self.rubric.name}'


def default_max_score(scale):
    return {
        Rubric.SCALE_5: 5,
        Rubric.SCALE_10: 10,
        Rubric.SCALE_100: 100,
    }.get(scale, 10)
