"""
Forgot-password flow:
  1. POST /api/password-reset/          → sends reset link via email
  2. GET  /password-reset/confirm/…     → renders the new-password form
  3. POST /password-reset/confirm/…     → validates & saves the new password
"""

import logging

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.shortcuts import render
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.views import View
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView

from notifications.email_service import send_password_reset_email, send_password_changed_email

logger = logging.getLogger(__name__)
User = get_user_model()


# ── API endpoint: request a password reset ───────────────────────────

class PasswordResetThrottle(AnonRateThrottle):
    scope = 'password_reset'


class RequestPasswordResetView(APIView):
    """
    POST /api/password-reset/
    Body: { "identifier": "<username or email>" }

    Always returns 200 to prevent user-enumeration.
    """
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetThrottle]

    def post(self, request):
        identifier = (request.data.get('identifier') or '').strip()
        if not identifier:
            return Response(
                {'detail': 'Please provide your student/employee ID or email address.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Look up by username OR email (case-insensitive email).
        user = User.objects.filter(
            Q(username=identifier) | Q(email__iexact=identifier),
            is_active=True,
        ).first()

        if user and user.email:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)
            # Use hash routing so the browser routes the path inside the Flutter single-page app
            reset_url = (
                f'{settings.FRONTEND_URL}/#/password-reset/confirm/{uid}/{token}/'
            )
            send_password_reset_email(user, reset_url)
            logger.info('password_reset: link sent to user_id=%s', user.pk)
        else:
            # No matching user or user has no email — log but don't reveal.
            logger.info('password_reset: no action for identifier=%r', identifier)

        # Same response regardless — prevents enumeration.
        return Response({
            'detail': (
                'If an account exists with that ID or email, '
                'a password reset link has been sent.'
            ),
        })


# ── API endpoint: confirm password reset ─────────────────────────────

class ConfirmPasswordResetAPIView(APIView):
    """
    POST /api/password-reset/confirm/
    Body: { "uidb64": "...", "token": "...", "new_password": "...", "confirm_password": "..." }

    Validates the reset token and user, sets the new password, and returns a JSON response.
    """
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetThrottle]

    def _get_user(self, uidb64):
        try:
            uid = force_str(urlsafe_base64_decode(uidb64))
            return User.objects.get(pk=uid)
        except (TypeError, ValueError, OverflowError, User.DoesNotExist):
            return None

    def post(self, request):
        uidb64 = request.data.get('uidb64')
        token = request.data.get('token')
        new_password = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        if not uidb64 or not token:
            return Response(
                {'detail': 'Invalid request parameters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = self._get_user(uidb64)
        if user is None or not default_token_generator.check_token(user, token):
            return Response(
                {'detail': 'This password reset link is invalid or has expired.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not new_password:
            return Response(
                {'detail': 'Password is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password != confirm_password:
            return Response(
                {'detail': 'New password and confirmation do not match.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            validate_password(new_password, user=user)
        except ValidationError as exc:
            return Response(
                {'detail': exc.messages[0]},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.set_password(new_password)
        user.save(update_fields=['password'])

        # Send confirmation email (best-effort).
        send_password_changed_email(user)

        logger.info('password_reset: user_id=%s successfully reset password', user.pk)
        return Response({'detail': 'Your password has been reset successfully.'})

