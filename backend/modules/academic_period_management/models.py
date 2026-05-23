import re

from django.core.exceptions import ValidationError
from django.db import models, transaction


SCHOOL_YEAR_PATTERN = re.compile(r'^\d{4}-\d{4}$')


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
