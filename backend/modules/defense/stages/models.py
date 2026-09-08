from django.core.exceptions import ValidationError
from django.db import models
from django.utils.text import slugify


DEFAULT_PANEL_WEIGHT = 50
DEFAULT_ADVISER_WEIGHT = 30
DEFAULT_PEER_WEIGHT = 20


import re


def clean_custom_code(raw_value):
    s = re.sub(r'[\s/]+', '-', raw_value.strip())
    s = re.sub(r'[^a-zA-Z0-9_-]', '', s)
    return s


class StageDeliverable(models.Model):
    TYPE_PRE = 'pre'
    TYPE_POST = 'post'

    TYPE_CHOICES = (
        (TYPE_PRE, 'Pre-Defense'),
        (TYPE_POST, 'Post-Defense'),
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
    archive_note = models.TextField(blank=True)
    archive_file_template = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Template for archive filename. Variables: {year}, {course}, {project}, {stage}, {deliverable}, {semester}',
    )
    is_restricted = models.BooleanField(
        default=False,
        help_text='If checked, this post-defense deliverable will be hidden from the public Project Repository.',
    )
    is_defense_material = models.BooleanField(
        default=True,
        help_text='If true, this pre-defense deliverable is visible to defense panelists during oral grading.',
    )
    VERDICT_CONDITION_ALL_PASS = 'all_pass'
    VERDICT_CONDITION_REVISIONS_ONLY = 'revisions_only'
    VERDICT_CONDITION_CHOICES = (
        (VERDICT_CONDITION_ALL_PASS, 'All Passing Defenses'),
        (VERDICT_CONDITION_REVISIONS_ONLY, 'Revisions Verdict Only'),
    )
    verdict_condition = models.CharField(
        max_length=20,
        choices=VERDICT_CONDITION_CHOICES,
        default=VERDICT_CONDITION_ALL_PASS,
        help_text='Condition under which this post-defense deliverable is required.',
    )
    FORMAT_ANY = 'any'
    FORMAT_PDF = 'pdf'
    FORMAT_VIDEO = 'video'
    FORMAT_IMAGE = 'image'
    FORMAT_PRESENTATION = 'presentation'
    FORMAT_DOCUMENT = 'document'
    FORMAT_SPREADSHEET = 'spreadsheet'
    FORMAT_ARCHIVE = 'archive'
    FORMAT_AUDIO = 'audio'

    FORMAT_CHOICES = (
        (FORMAT_ANY, 'Any File Format'),
        (FORMAT_PDF, 'PDF Document (.pdf)'),
        (FORMAT_VIDEO, 'Video (.mp4, .mov, .webm)'),
        (FORMAT_IMAGE, 'Image / Poster (.png, .jpg, .svg)'),
        (FORMAT_PRESENTATION, 'Presentation Slides (.pptx, .ppt, .pdf)'),
        (FORMAT_DOCUMENT, 'Word / Document (.docx, .doc, .pdf)'),
        (FORMAT_SPREADSHEET, 'Spreadsheet (.xlsx, .xls, .csv)'),
        (FORMAT_ARCHIVE, 'Archive / Source Code (.zip, .rar, .7z)'),
        (FORMAT_AUDIO, 'Audio Recording (.mp3, .wav, .aac)'),
    )

    file_format = models.CharField(
        max_length=30,
        choices=FORMAT_CHOICES,
        default=FORMAT_ANY,
        blank=True,
        help_text='Allowed file format category for this deliverable.',
    )
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
    is_presentation_only = models.BooleanField(
        default=False,
        help_text='If true, this stage is an oral presentation, pitch, or demo day with no file uploads required.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_stages_stage'
        ordering = ['display_order', 'label']

    def save(self, *args, **kwargs):
        if self.pk:
            old = DefenseStage.objects.filter(pk=self.pk).values('label', 'code').first()
            if old:
                old_label_slug = slugify(old['label'])
                old_code = old.get('code') or ''
                if not self.code or self.code.lower() == old_label_slug:
                    self.code = unique_stage_code(self.label, instance_id=self.pk, is_custom=False)
                else:
                    is_custom = self.code.lower() != old_code.lower() or self.code.lower() != old_label_slug
                    self.code = unique_stage_code(self.code, instance_id=self.pk, is_custom=is_custom)
            else:
                self.code = unique_stage_code(self.code or self.label, instance_id=self.pk, is_custom=bool(self.code))
        else:
            self.code = unique_stage_code(self.code or self.label, instance_id=self.pk, is_custom=bool(self.code))
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
        from grading.grades.models import TeamGrade
        from django.db.models import Q

        TeamGrade.objects.filter(
            Q(defense_stage=self.defense_stage) | Q(semester=self.semester, scope=TeamGrade.SCOPE_CAPSTONE, stage_label__iexact=self.defense_stage.label),
            status=TeamGrade.STATUS_PENDING,
        ).update(
            defense_stage=self.defense_stage,
            panel_weight=self.panel_weight,
            adviser_weight=self.adviser_weight,
            peer_weight=self.peer_weight,
        )

    def as_weights_dict(self):
        return {
            'panel_weight': self.panel_weight,
            'adviser_weight': self.adviser_weight,
            'peer_weight': self.peer_weight,
        }

    def __str__(self):
        return f'{self.defense_stage.label} ({self.semester})'


def unique_stage_code(raw_value_or_label, instance_id=None, is_custom=False):
    if is_custom and raw_value_or_label and raw_value_or_label.strip():
        base_code = clean_custom_code(raw_value_or_label) or 'stage'
    else:
        base_code = slugify(raw_value_or_label) or 'stage'

    code = base_code
    index = 2
    queryset = DefenseStage.objects.filter(code__iexact=code)
    if instance_id is not None:
        queryset = queryset.exclude(pk=instance_id)

    while queryset.exists():
        code = f'{base_code}-{index}'
        queryset = DefenseStage.objects.filter(code__iexact=code)
        if instance_id is not None:
            queryset = queryset.exclude(pk=instance_id)
        index += 1

    return code
