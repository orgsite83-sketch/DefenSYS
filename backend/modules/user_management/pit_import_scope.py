"""Scope checks shared by both PIT enrollment import routes."""
from rest_framework.exceptions import PermissionDenied
from django.db.models import Q
from academic_period_management.models import Semester
from student_teams.models import StudentTeam
from student_teams.team_levels import is_capstone_scope
from .academic_records.models import StudentAcademicRecord


def require_pit_import_scope(user, semester):
    year = (getattr(user, 'pit_lead_year', '') or '').strip()
    if year not in ('1st Year', '2nd Year', '3rd Year'):
        raise PermissionDenied('An assigned PIT year is required to import students.')
    if not semester or not Semester.objects.filter(pk=semester.pk, is_active=True).exists():
        raise PermissionDenied('PIT enrollment imports require the active semester.')
    if is_capstone_scope(year, semester):
        raise PermissionDenied('Student import for this term is handled under Capstone.')
    return year


def locked_student_for_pit_import(user, student, semester):
    """Call inside the import transaction, before profile or academic writes."""
    year = require_pit_import_scope(user, semester)
    student = type(student).objects.select_for_update().get(pk=student.pk)
    if student.role != 'student':
        raise PermissionDenied('PIT enrollment imports cannot modify staff accounts.')
    records = StudentAcademicRecord.objects.select_for_update().filter(student=student, semester=semester)
    if any(record.year_level != year for record in records):
        raise PermissionDenied('Existing enrollment is outside your assigned PIT year. Ask Admin to review it.')
    teams = StudentTeam.objects.filter(Q(memberships__student=student) | Q(leader=student), semester=semester)
    if teams.exclude(level__icontains='PIT').exists() or teams.exclude(year_level=year).exists():
        raise PermissionDenied('Existing team membership is outside your PIT scope. Ask Admin to review it.')
    return student
