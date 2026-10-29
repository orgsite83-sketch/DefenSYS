"""Enrollment requirements shared by explicit roster previews and writes.

Term activation is a separate operation: eligible existing teams may continue
before destination enrollment rollover. This validator never enrolls students.
"""
from django.contrib.auth import get_user_model
from rest_framework.exceptions import ValidationError
from user_management.academic_records.models import StudentAcademicRecord


def missing_enrollment_issues(student_ids, semester, *, lock=False):
    ids = set(student_ids)
    if not ids:
        return []
    if semester is None:
        raise ValidationError({'semester_id': 'No active semester is configured.'})
    records = StudentAcademicRecord.objects.filter(semester=semester, student_id__in=ids).order_by('pk')
    if lock:
        records = records.select_for_update()
    missing = ids - set(records.values_list('student_id', flat=True))
    if not missing:
        return []
    students = {student.pk: student for student in get_user_model().objects.filter(pk__in=missing)}
    issues = []
    for student_id in sorted(missing):
        student = students.get(student_id)
        name = student.get_full_name().strip() if student else ''
        if student:
            label = f'{name} ({student.username})' if name else f'Student {student.username}'
        else:
            label = f'Student account #{student_id}'
        issues.append(f'{label} is not enrolled in {semester.display_name}. '
                      'Enroll this student for that semester before adding them to the team.')
    return issues


def require_roster_enrollment(student_ids, semester, *, lock=False):
    issues = missing_enrollment_issues(student_ids, semester, lock=lock)
    if issues:
        raise ValidationError({'member_ids': issues}, code='semester_enrollment_required')
