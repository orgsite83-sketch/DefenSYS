"""JWT access tokens for guest panelist codes (no User account)."""

from datetime import timedelta

from django.utils import timezone
from rest_framework_simplejwt.tokens import AccessToken

from user_management.models import GuestPanelistCode


def get_guest_code_or_none(code: str):
    try:
        guest_code = GuestPanelistCode.objects.select_related(
            'defense_schedule',
            'defense_schedule__team',
            'defense_schedule__defense_stage',
            'defense_schedule__rubric',
        ).get(code=code.upper(), is_active=True)
    except GuestPanelistCode.DoesNotExist:
        return None

    if guest_code.expires_at and guest_code.expires_at < timezone.now():
        return None
    return guest_code


def create_guest_access_token(guest_code: GuestPanelistCode) -> str:
    schedule = guest_code.defense_schedule
    team = schedule.team
    token = AccessToken()
    token.set_exp(lifetime=timedelta(hours=8))
    token['guest_panelist'] = True
    token['guest_code_id'] = guest_code.id
    token['guest_code'] = guest_code.code
    token['defense_schedule_id'] = schedule.id
    token['team_id'] = team.id if team else None
    token['guest_name'] = guest_code.guest_name
    return str(token)


def guest_user_payload(guest_code: GuestPanelistCode) -> dict:
    schedule = guest_code.defense_schedule
    team = schedule.team
    return {
        'id': guest_code.id,
        'role': 'guest_panelist',
        'name': guest_code.guest_name,
        'guest_name': guest_code.guest_name,
        'guest_code_id': guest_code.id,
        'guest_code': guest_code.code,
        'defense_schedule_id': schedule.id,
        'defenseId': schedule.id,
        'team_id': team.id if team else None,
        'team_name': team.name if team else '',
        'is_guest_panelist': True,
    }
