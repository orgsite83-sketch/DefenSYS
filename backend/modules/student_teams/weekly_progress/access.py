"""One authorization policy for report metadata and private file bytes."""
from authentication_access_control.scopes import is_admin_user
from django.db.models import F, Q
from .models import WeeklyProgressReport


def reports_for(user):
    reports = WeeklyProgressReport.objects.select_related('team', 'team__semester', 'student')
    if not user or not user.is_authenticated:
        return reports.none()
    if is_admin_user(user):
        return reports
    if user.role == 'student':
        # Managed collections belong to the team/week. A new active leader may
        # continue that team's reports without rewriting the original uploader.
        return reports.filter(Q(student=user) | Q(period__isnull=False,
            team__leader=user, team__memberships__student=user, semester__is_active=True,
            semester_id=F('team__semester_id'), project_version=F('team__project_version'))).distinct()
    if user.role == 'faculty' and user.is_adviser:
        return reports.filter(team__adviser=user, team__level__icontains='Capstone')
    return reports.none()


def can_write_report(user, report):
    return bool(user.role == 'student' and report.student_id == user.pk
                and report.team.leader_id == user.pk and report.team.is_capstone
                and report.team.semester.is_active)
