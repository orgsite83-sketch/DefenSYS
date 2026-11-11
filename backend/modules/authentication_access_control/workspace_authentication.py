"""Request-local workspace narrowing; account identity and stored roles never change."""
from rest_framework.exceptions import PermissionDenied
from rest_framework_simplejwt.authentication import JWTAuthentication

from .workspace_roles import is_adviser, is_institutional_staff, is_pit_lead


class WorkspaceJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)
        if result is not None:
            bind_workspace(result[0], getattr(request, 'headers', {}))
            workspace = getattr(result[0], '_workspace', '')
            selected = getattr(request, 'query_params', {}).get('workspace', '').strip()
            if (workspace and selected and not getattr(request, 'path', '').startswith('/api/curriculum-analytics')
                    and selected != workspace and not (selected == 'operations' and workspace == 'pit_lead')):
                raise PermissionDenied('The request must use the selected workspace.')
        return result


def bind_workspace(user, headers):
    # Attach only transient metadata to the authenticated model. Never change
    # role/is_superuser, and never save a user while resolving navigation.
    workspace = headers.get('X-Defensys-Workspace', '').strip()
    user._workspace = ''
    user._workspace_year = ''
    user._workspace_section = ''
    if not workspace:
        return
    allowed = False
    if is_institutional_staff(user):
        if workspace == 'adviser':
            allowed = is_adviser(user)
        elif workspace == 'pit_lead':
            allowed = is_pit_lead(user)
        elif workspace in ('panelist', 'documenter'):
            allowed = bool(getattr(user, f'is_{workspace}', False))
        elif workspace == 'instructor':
            from academic_period_management.services import active_semester
            from student_teams.formation_access import instructor_sections
            year = headers.get('X-Defensys-Year', '').strip()
            section = headers.get('X-Defensys-Section', '').strip()
            assignments = instructor_sections(user, active_semester(), year or None)
            if section:
                assignments = assignments.filter(section=section)
            allowed = assignments.exists()
            user._workspace_year, user._workspace_section = year, section
    if not allowed:
        raise PermissionDenied('This workspace is no longer assigned to your account. Refresh and choose an available workspace.')
    user._workspace = workspace
