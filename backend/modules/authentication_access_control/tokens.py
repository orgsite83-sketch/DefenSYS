"""JWT tokens with remember-me vs standard refresh lifetimes."""

from datetime import timedelta

from django.conf import settings
from rest_framework_simplejwt.tokens import RefreshToken

REMEMBER_ME_CLAIM = 'rm'


def _standard_refresh_lifetime() -> timedelta:
    return getattr(
        settings,
        'SIMPLE_JWT_REFRESH_STANDARD',
        timedelta(hours=12),
    )


def _remember_refresh_lifetime() -> timedelta:
    return getattr(
        settings,
        'SIMPLE_JWT_REFRESH_REMEMBER',
        timedelta(days=7),
    )


class DefensysRefreshToken(RefreshToken):
    @classmethod
    def for_user(cls, user, *, remember_me: bool = False):
        token = super().for_user(user)
        if remember_me:
            token[REMEMBER_ME_CLAIM] = True
            lifetime = _remember_refresh_lifetime()
        else:
            token[REMEMBER_ME_CLAIM] = False
            lifetime = _standard_refresh_lifetime()
        token.set_exp(lifetime=lifetime)
        return token

    @property
    def remember_me(self) -> bool:
        return bool(self.get(REMEMBER_ME_CLAIM))
