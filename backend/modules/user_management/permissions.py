from rest_framework.permissions import BasePermission


def _authenticated_user(request):
    user = request.user
    return user if user and user.is_authenticated else None


class IsSystemAdmin(BasePermission):
    message = 'Only administrators can manage users.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and (getattr(user, 'role', None) == 'admin' or user.is_superuser)
        )


class IsAdminRole(BasePermission):
    message = 'Only administrators can access this dashboard.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and (getattr(user, 'role', None) == 'admin' or user.is_superuser)
        )


class IsFacultyRole(BasePermission):
    message = 'Only faculty can access this dashboard.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and (
                getattr(user, 'role', None) in ('faculty', 'admin')
                or user.is_superuser
            )
        )


class IsStudentRole(BasePermission):
    message = 'Only students can access this dashboard.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(user and getattr(user, 'role', None) == 'student')


class IsPanelist(BasePermission):
    message = 'Only assigned panelists can access this dashboard.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and (
                getattr(user, 'is_panelist', False)
                or getattr(user, 'role', None) == 'admin'
                or user.is_superuser
            )
        )


class IsPitLead(BasePermission):
    message = 'Only PIT Leads can access this resource.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and getattr(user, 'is_pit_lead', False)
            and bool((getattr(user, 'pit_lead_year', None) or '').strip())
        )


class IsPitLeadOrAdmin(BasePermission):
    message = 'Only administrators and PIT Leads can access this resource.'

    def has_permission(self, request, view):
        user = _authenticated_user(request)
        return bool(
            user
            and (
                getattr(user, 'role', None) == 'admin'
                or user.is_superuser
                or (
                    getattr(user, 'is_pit_lead', False)
                    and bool((getattr(user, 'pit_lead_year', None) or '').strip())
                )
            )
        )


class CanManageTeams(BasePermission):
    """
    Permission class that allows system administrators, PIT Leads, and Uploaders
    to access student teams.
    - Admins and PIT Leads: Full access (read/write)
    - Uploaders: Read-only access (for document uploads)
    """
    message = 'Only administrators, PIT Leads, PIT Instructors, and uploaders can access teams.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        
        # Allow admins (full access)
        if getattr(user, 'role', None) == 'admin' or user.is_superuser:
            return True
        
        # Allow PIT Leads (full access)
        if getattr(user, 'is_pit_lead', False):
            return True

        # Allow PIT Instructors to read/update assigned-section teams.
        if request.method in ('GET', 'PATCH', 'DELETE'):
            from user_management.models import PitInstructorAssignment

            if PitInstructorAssignment.objects.filter(faculty=user, is_active=True).exists():
                return True
        
        # Allow uploaders (read-only access for GET requests)
        if getattr(user, 'is_uploader', False) and request.method == 'GET':
            return True
        
        return False
