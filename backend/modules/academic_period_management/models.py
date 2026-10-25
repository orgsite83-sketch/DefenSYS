import re

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models, transaction


SCHOOL_YEAR_PATTERN = re.compile(r'^\d{4}-\d{4}$')
SCHOOL_YEAR_LOCK_REASON = (
    'School year labels are locked after semesters are added. '
    'A used year requires an audited correction to preserve its calendar and academic history.'
)


def validate_school_year_label(value):
    if not SCHOOL_YEAR_PATTERN.fullmatch(value or ''):
        raise ValidationError('School year must use YYYY-YYYY format.')

    start, end = [int(part) for part in value.split('-')]
    if end != start + 1:
        raise ValidationError('School year range must be consecutive.')


class SchoolYear(models.Model):
    label = models.CharField(max_length=9, unique=True, validators=[validate_school_year_label])
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-label']

    def __str__(self):
        return self.label

    @property
    def can_edit_label(self):
        return not self.semesters.exists()

    def clean(self):
        super().clean()
        if (self.pk and SchoolYear.objects.filter(pk=self.pk).exclude(label=self.label).exists()
                and not self.can_edit_label):
            raise ValidationError({'label': SCHOOL_YEAR_LOCK_REASON})

    def save(self, *args, **kwargs):
        # Lock the parent before checking children: semester inserts need a
        # conflicting FK lock, so a concurrent first semester cannot slip in.
        with transaction.atomic():
            if self.pk and (kwargs.get('update_fields') is None or 'label' in kwargs['update_fields']):
                previous = SchoolYear.objects.select_for_update().filter(pk=self.pk).first()
                if previous and previous.label != self.label and previous.semesters.exists():
                    raise ValidationError({'label': SCHOOL_YEAR_LOCK_REASON})
            super().save(*args, **kwargs)


class Semester(models.Model):
    FIRST = '1st Semester'
    SECOND = '2nd Semester'
    SUMMER = 'Summer'

    TERM_CHOICES = (
        (FIRST, FIRST),
        (SECOND, SECOND),
        (SUMMER, SUMMER),
    )

    school_year = models.ForeignKey(SchoolYear, related_name='semesters', on_delete=models.CASCADE)
    label = models.CharField(max_length=20, choices=TERM_CHOICES)
    is_active = models.BooleanField(default=False)
    starts_on = models.DateField(null=True, blank=True)
    ends_on = models.DateField(null=True, blank=True)
    capstone_peer_evaluation_enabled = models.BooleanField(
        default=True,
        help_text='When off, students cannot use peer evaluation for Capstone teams.',
    )
    capstone_adviser_grading_enabled = models.BooleanField(
        default=True,
        help_text='When off, advisers cannot submit adviser grades for Capstone teams.',
    )
    capstone_team_creation_enabled = models.BooleanField(
        default=False,
        help_text='When on, admins can create or bulk-import new capstone teams (Capstone 1 intake).',
    )
    PHASE_NONE = 'none'
    PHASE_CAPSTONE_1 = 'capstone_1'
    PHASE_CAPSTONE_2 = 'capstone_2'
    PHASE_CHOICES = (
        (PHASE_NONE, 'None'),
        (PHASE_CAPSTONE_1, 'Capstone 1 intake'),
        (PHASE_CAPSTONE_2, 'Capstone 2 continue'),
    )
    capstone_program_phase = models.CharField(
        max_length=20,
        choices=PHASE_CHOICES,
        default=PHASE_NONE,
        help_text='Capstone 1 = new team intake; Capstone 2 = same teams bumped via rollover.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['school_year__label', 'id']
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(starts_on__isnull=True, ends_on__isnull=True)
                    | (models.Q(starts_on__isnull=False, ends_on__isnull=False)
                       & models.Q(starts_on__lt=models.F('ends_on')))
                ),
                name='semester_calendar_ordered_pair',
            ),
            models.UniqueConstraint(
                fields=['school_year', 'label'],
                name='unique_semester_per_school_year',
            ),
            models.UniqueConstraint(
                fields=['is_active'],
                condition=models.Q(is_active=True),
                name='unique_active_semester',
            ),
        ]

    @property
    def display_name(self):
        return f'{self.label}, A.Y. {self.school_year.label}'

    def save(self, *args, **kwargs):
        with transaction.atomic():
            if self.is_active:
                Semester.objects.exclude(pk=self.pk).filter(is_active=True).update(is_active=False)
            super().save(*args, **kwargs)

    def __str__(self):
        return self.display_name


class SemesterTransitionLog(models.Model):
    operation = models.CharField(max_length=12, default='activation', choices=[('activation', 'Activation'), ('returning', 'Returning teams')])
    request_id = models.CharField(max_length=64, null=True, blank=True, unique=True)
    preview_revision = models.CharField(max_length=64, blank=True)
    from_semester = models.ForeignKey(
        Semester,
        related_name='transition_logs_from',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    to_semester = models.ForeignKey(
        Semester,
        related_name='transition_logs_to',
        on_delete=models.PROTECT,
    )
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='semester_transition_logs',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    forced = models.BooleanField(default=False)
    reason = models.TextField(blank=True)
    impact_snapshot = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']

    def __str__(self):
        source = self.from_semester.display_name if self.from_semester else 'No active semester'
        return f'{source} -> {self.to_semester.display_name}'
