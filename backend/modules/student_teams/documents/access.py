"""Private document access, independent of team-directory/PM visibility."""
from django.db.models import Q
from authentication_access_control.scopes import is_admin_user, is_pit_lead_only, section_instructor_section_filters
from student_teams.models import StudentTeam


def document_teams_for(user):
    teams = StudentTeam.objects.all()
    if not user or not user.is_authenticated:
        return teams.none()
    if is_admin_user(user):
        return teams
    allowed = Q(leader=user) | Q(memberships__student=user)
    if user.role == 'faculty':
        allowed |= Q(adviser=user)
        allowed |= Q(level__icontains='PIT') & section_instructor_section_filters(user)
        year = (getattr(user, 'pit_lead_year', '') or '').strip()
        if is_pit_lead_only(user) and year:
            allowed |= Q(level__icontains='PIT', year_level=year)
    if getattr(user, 'is_uploader', False):
        allowed |= Q(semester__is_active=True)
    return teams.filter(allowed).distinct()


def can_write_documents(user, team):
    from student_teams.team_levels import is_capstone_scope
    if team.is_pit and is_capstone_scope(team.year_level, team.semester):
        return False
    return bool(team.semester.is_active and document_teams_for(user).filter(pk=team.pk).exists())
