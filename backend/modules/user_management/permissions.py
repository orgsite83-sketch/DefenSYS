from rest_framework.permissions import BasePermission


class IsSystemAdmin(BasePermission):
    message = 'Only administrators can manage users.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (getattr(user, 'role', None) == 'admin' or user.is_superuser)
        )


class CanManageTeams(BasePermission):
    """
    Permission class that allows system administrators, PIT Leads, and Uploaders
    to access student teams.
    - Admins and PIT Leads: Full access (read/write)
    - Uploaders: Read-only access (for document uploads)
    """
    message = 'Only administrators, PIT Leads, and uploaders can access teams.'

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
        
        # Allow uploaders (read-only access for GET requests)
        if getattr(user, 'is_uploader', False) and request.method == 'GET':
            return True
        
        return False
