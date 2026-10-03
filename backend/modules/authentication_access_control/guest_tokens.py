"""JWT access tokens for guest panelist codes (no User account)."""

from datetime import timedelta

from django.utils import timezone
from rest_framework_simplejwt.tokens import AccessToken

from user_management.models import GuestPanelistCode
from user_management.external_evaluators import invitation_is_available, invitation_schedule_ids, primary_guest_schedule


def get_guest_code_or_none(code: str):
    try:
        guest_code = GuestPanelistCode.objects.select_related(
            'evaluator',
            'defense_schedule',
            'defense_schedule__team',
            'defense_schedule__defense_stage',
            'defense_schedule__rubric',
        ).get(code=code.upper(), is_active=True)
    except GuestPanelistCode.DoesNotExist:
        return None

    if not invitation_is_available(guest_code):
        return None
    return guest_code


def create_guest_access_token(guest_code: GuestPanelistCode) -> str:
    schedule = primary_guest_schedule(guest_code)
    team = schedule.team
    token = AccessToken()
    token.set_exp(lifetime=timedelta(hours=8))
    if guest_code.expires_at:
        token['exp'] = min(token['exp'], int(guest_code.expires_at.timestamp()))
    token['guest_panelist'] = True
    token['guest_code_id'] = guest_code.id
    token['access_version'] = guest_code.access_version
    token['guest_code'] = guest_code.code
    token['defense_schedule_id'] = schedule.id
    token['team_id'] = team.id if team else None
    token['guest_name'] = guest_code.guest_name
    return str(token)


def guest_user_payload(guest_code: GuestPanelistCode) -> dict:
    schedule = primary_guest_schedule(guest_code)
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
        'schedule_ids': invitation_schedule_ids(guest_code),
        'expires_at': guest_code.expires_at.isoformat() if guest_code.expires_at else None,
    }
