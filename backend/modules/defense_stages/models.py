from django.db import models
from django.utils.text import slugify


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
        ordering = ['display_order', 'label']

    def save(self, *args, **kwargs):
        self.code = unique_stage_code(self.label, self.pk)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.label


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
