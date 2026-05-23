from django.core.exceptions import ValidationError
from django.db import models
from django.utils.text import slugify


DEFAULT_PANEL_WEIGHT = 50
DEFAULT_ADVISER_WEIGHT = 30
DEFAULT_PEER_WEIGHT = 20


class StageDeliverable(models.Model):
    TYPE_PRE = 'pre'
    TYPE_VAULT = 'vault'

    TYPE_CHOICES = (
        (TYPE_PRE, 'Pre-Defense'),
        (TYPE_VAULT, 'Vault'),
    )

    defense_stage = models.ForeignKey(
        'DefenseStage',
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
    required = models.BooleanField(default=False)
    display_order = models.PositiveSmallIntegerField(default=1)
    vault_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_stages_stagedeliverable'
        ordering = ['display_order', 'deliverable_id']
        constraints = [
            models.UniqueConstraint(
                fields=['defense_stage', 'deliverable_id'],
                name='unique_deliverable_per_stage',
            ),
        ]

    def __str__(self):
        return f'{self.defense_stage.label} - {self.label}'


class DefenseStage(models.Model):
    label = models.CharField(max_length=120, unique=True)
    code = models.SlugField(max_length=140, unique=True, blank=True)
    display_order = models.PositiveSmallIntegerField(default=1)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_stages_stage'
        ordering = ['display_order', 'label']

    def save(self, *args, **kwargs):
        self.code = unique_stage_code(self.label, self.pk)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.label


class StageGradingConfig(models.Model):
    """Panel / Adviser / Peer grade composition for a capstone defense stage per semester."""

    defense_stage = models.ForeignKey(
        DefenseStage,
        related_name='grading_configs',
        on_delete=models.CASCADE,
    )
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='stage_grading_configs',
        on_delete=models.CASCADE,
    )
    panel_weight = models.PositiveSmallIntegerField(default=DEFAULT_PANEL_WEIGHT)
    adviser_weight = models.PositiveSmallIntegerField(default=DEFAULT_ADVISER_WEIGHT)
    peer_weight = models.PositiveSmallIntegerField(default=DEFAULT_PEER_WEIGHT)
    panel_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='stage_configs_as_panel',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    adviser_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='stage_configs_as_adviser',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    peer_rubric = models.ForeignKey(
        'grading.Rubric',
        related_name='stage_configs_as_peer',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    is_officially_complete = models.BooleanField(default=False)
    peer_grading_enabled = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_stages_gradingconfig'
        constraints = [
            models.UniqueConstraint(
                fields=['defense_stage', 'semester'],
                name='unique_grading_config_per_stage_semester',
            ),
        ]

    def clean(self):
        errors = {}
        total = self.panel_weight + self.adviser_weight + self.peer_weight
        if total != 100:
            errors['weights'] = 'Panel, adviser, and peer weights must total 100%.'
        for field in ['panel_weight', 'adviser_weight', 'peer_weight']:
            if getattr(self, field) > 100:
                errors[field] = 'Weight cannot be greater than 100%.'
        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def as_weights_dict(self):
        return {
            'panel_weight': self.panel_weight,
            'adviser_weight': self.adviser_weight,
            'peer_weight': self.peer_weight,
        }

    def __str__(self):
        return f'{self.defense_stage.label} ({self.semester})'


def unique_stage_code(label, instance_id=None):
    base_code = slugify(label) or 'stage'
    code = base_code
    index = 2
    queryset = DefenseStage.objects.filter(code=code)
    if instance_id is not None:
        queryset = queryset.exclude(pk=instance_id)

    while queryset.exists():
        code = f'{base_code}-{index}'
        queryset = DefenseStage.objects.filter(code=code)
        if instance_id is not None:
            queryset = queryset.exclude(pk=instance_id)
        index += 1

    return code
