"""Authenticate guest panelist JWTs (custom claims, no User row)."""

from rest_framework.permissions import BasePermission
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken


class GuestPanelistPrincipal:
    """Minimal principal for guest panelist requests."""

    is_authenticated = True
    is_guest_panelist = True
    is_active = True
    is_anonymous = False

    def __init__(self, token):
        self.token = token
        self.pk = token.get('guest_code_id')
        self.id = self.pk
        self.guest_code_id = self.pk
        self.guest_code = token.get('guest_code', '')
        self.guest_name = token.get('guest_name', 'Guest')
        self.defense_schedule_id = token.get('defense_schedule_id')
        self.team_id = token.get('team_id')
        self.username = f'guest:{self.guest_code}'
        self.role = 'guest_panelist'

    def __str__(self):
        return self.username


class GuestJWTAuthentication(JWTAuthentication):
    """Accept only access tokens issued for guest panelists."""

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            return None
        raw_token = self.get_raw_token(header)
        if raw_token is None:
            return None
        try:
            validated_token = self.get_validated_token(raw_token)
        except InvalidToken:
            return None
        if not validated_token.get('guest_panelist'):
            return None
        return GuestPanelistPrincipal(validated_token), validated_token


class IsGuestPanelist(BasePermission):
    message = 'Guest panelist authentication required.'

    def has_permission(self, request, view):
        user = getattr(request, 'user', None)
        return bool(user and getattr(user, 'is_guest_panelist', False))
