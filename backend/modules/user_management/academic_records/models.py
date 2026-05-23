from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class StudentAcademicRecord(models.Model):
    FIRST_YEAR = '1st Year'
    SECOND_YEAR = '2nd Year'
    THIRD_YEAR = '3rd Year'
    FOURTH_YEAR = '4th Year'

    YEAR_LEVEL_CHOICES = (
        (FIRST_YEAR, FIRST_YEAR),
        (SECOND_YEAR, SECOND_YEAR),
        (THIRD_YEAR, THIRD_YEAR),
        (FOURTH_YEAR, FOURTH_YEAR),
    )

    ACTION_MANUAL = 'manual'
    ACTION_PROMOTE = 'promote'
    ACTION_RETAIN = 'retain'

    ACTION_CHOICES = (
        (ACTION_MANUAL, 'Manual'),
        (ACTION_PROMOTE, 'Promote'),
        (ACTION_RETAIN, 'Retain'),
    )

    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='academic_records',
        on_delete=models.CASCADE,
    )
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='student_records',
        on_delete=models.CASCADE,
    )
    year_level = models.CharField(max_length=20, choices=YEAR_LEVEL_CHOICES)
    action = models.CharField(max_length=20, choices=ACTION_CHOICES, default=ACTION_MANUAL)
    rolled_from = models.ForeignKey(
        'self',
        related_name='rollover_children',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'user_management'
        db_table = 'student_academic_records_studentacademicrecord'
        ordering = ['-created_at', 'student__username']
        constraints = [
            models.UniqueConstraint(
                fields=['student', 'semester'],
                name='unique_student_record_per_semester',
            ),
        ]

    @property
    def student_name(self):
        full_name = f'{self.student.first_name} {self.student.last_name}'.strip()
        return full_name or self.student.username

    @property
    def school_year(self):
        return self.semester.school_year

    def clean(self):
        if self.student_id and getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Academic records can only be assigned to student users.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.student_name} - {self.year_level} - {self.semester.display_name}'
