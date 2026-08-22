"""
Forgot-password OTP flow:
  1. POST /api/password-reset/            → generates 6-digit OTP & sends via email
  2. POST /api/password-reset/verify-otp/ → verifies 6-digit OTP & issues reset token
  3. POST /api/password-reset/confirm/    → validates reset token & updates password
"""

import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.utils import timezone
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView

from authentication_access_control.models import PasswordResetOTP
from notifications.email_service import (
    send_password_changed_email,
    send_password_reset_otp_email,
)

logger = logging.getLogger(__name__)
User = get_user_model()


def _mask_email(email: str) -> str:
    """Mask email for safe client-side display (e.g., j***e@example.com)."""
    if not email or '@' not in email:
        return ''
    parts = email.split('@', 1)
    name, domain = parts[0], parts[1]
    if len(name) <= 2:
        masked_name = name[0] + '*'
    else:
        masked_name = name[0] + ('*' * min(len(name) - 2, 6)) + name[-1]
    return f'{masked_name}@{domain}'


# ── Throttles ────────────────────────────────────────────────────────

class PasswordResetThrottle(AnonRateThrottle):
    scope = 'password_reset'


class PasswordResetVerifyThrottle(AnonRateThrottle):
    scope = 'password_reset_verify'


class PasswordResetConfirmThrottle(AnonRateThrottle):
    scope = 'password_reset_confirm'



# ── Step 1: Request 6-digit OTP ──────────────────────────────────────

class RequestPasswordResetView(APIView):
    """
    POST /api/password-reset/
    Body: { "identifier": "<username or email>" }

    Generates a 6-digit verification code and emails it to the user.
    Always returns 200 to prevent user enumeration.
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

        masked_email = ''
        if user and user.email:
            masked_email = _mask_email(user.email)
            # Invalidate previous unverified/unused OTPs for this user
            PasswordResetOTP.objects.filter(
                user=user,
                is_used=False,
            ).update(is_used=True)

            # Generate 6-digit numeric OTP
            otp_code = f'{secrets.randbelow(1000000):06d}'
            hashed_otp = make_password(otp_code)
            expiry_seconds = getattr(settings, 'PASSWORD_RESET_OTP_TIMEOUT', 600)
            expires_at = timezone.now() + timedelta(seconds=expiry_seconds)

            PasswordResetOTP.objects.create(
                user=user,
                otp_code_hash=hashed_otp,
                expires_at=expires_at,
            )

            email_sent = send_password_reset_otp_email(user, otp_code)
            if not email_sent:
                logger.error(
                    'password_reset: Failed to send OTP email to user_id=%s email=%s',
                    user.pk,
                    user.email,
                )
                return Response(
                    {
                        'detail': (
                            'Failed to send password reset email due to a mail delivery error. '
                            'Please try again later or contact support.'
                        )
                    },
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                )
            logger.info('password_reset: 6-digit OTP sent to user_id=%s', user.pk)
        else:
            logger.info('password_reset: no action for identifier=%r', identifier)

        # Generic response preventing user enumeration
        return Response({
            'detail': 'A 6-digit verification code has been sent to your email address.',
            'masked_email': masked_email,
        })


# ── Step 2: Verify 6-digit OTP ────────────────────────────────────────

class VerifyPasswordResetOTPView(APIView):
    """
    POST /api/password-reset/verify-otp/
    Body: { "identifier": "<username or email>", "otp_code": "123456" }

    Validates the 6-digit OTP code. If valid, generates and returns a single-use reset_token.
    """
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetVerifyThrottle]

    def post(self, request):
        identifier = (request.data.get('identifier') or '').strip()
        otp_code = (request.data.get('otp_code') or '').strip()

        if not identifier or not otp_code:
            return Response(
                {'detail': 'Please provide your ID/email and 6-digit verification code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(otp_code) != 6 or not otp_code.isdigit():
            return Response(
                {'detail': 'The verification code must be exactly 6 digits.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = User.objects.filter(
            Q(username=identifier) | Q(email__iexact=identifier),
            is_active=True,
        ).first()

        if not user:
            return Response(
                {'detail': 'Invalid or expired verification code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Find latest active OTP record for user
        otp_record = PasswordResetOTP.objects.filter(
            user=user,
            is_used=False,
            is_verified=False,
        ).first()

        if not otp_record:
            return Response(
                {'detail': 'No active verification code found. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Check expiration
        if otp_record.expires_at < timezone.now():
            return Response(
                {'detail': 'This verification code has expired. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Check brute-force attempts
        if otp_record.attempts >= 5:
            otp_record.is_used = True
            otp_record.save(update_fields=['is_used'])
            return Response(
                {'detail': 'Too many incorrect attempts. This code is now invalid. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Validate code
        if not check_password(otp_code, otp_record.otp_code_hash):
            otp_record.attempts += 1
            otp_record.save(update_fields=['attempts'])
            remaining = max(0, 5 - otp_record.attempts)
            if remaining == 0:
                otp_record.is_used = True
                otp_record.save(update_fields=['is_used'])
                return Response(
                    {'detail': 'Too many incorrect attempts. This code is now invalid. Please request a new code.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {'detail': f'Incorrect verification code. {remaining} attempt(s) remaining.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # OTP verified! Generate secure reset token
        reset_token = secrets.token_urlsafe(32)
        otp_record.is_verified = True
        otp_record.reset_token = reset_token
        otp_record.save(update_fields=['is_verified', 'reset_token'])

        uidb64 = urlsafe_base64_encode(force_bytes(user.pk))
        return Response({
            'detail': 'Verification code confirmed.',
            'reset_token': reset_token,
            'uidb64': uidb64,
        })


# ── Step 3: Confirm new password ─────────────────────────────────────

class ConfirmPasswordResetAPIView(APIView):
    """
    POST /api/password-reset/confirm/
    Body: { "uidb64": "...", "reset_token": "...", "new_password": "...", "confirm_password": "..." }
    (Also supports legacy 'token' parameter for backwards compatibility)
    """
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetConfirmThrottle]

    def _get_user(self, uidb64):
        try:
            uid = force_str(urlsafe_base64_decode(uidb64))
            return User.objects.get(pk=uid)
        except (TypeError, ValueError, OverflowError, User.DoesNotExist):
            return None

    def post(self, request):
        uidb64 = request.data.get('uidb64')
        reset_token = request.data.get('reset_token') or request.data.get('token')
        new_password = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        if not uidb64 or not reset_token:
            return Response(
                {'detail': 'Invalid request parameters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = self._get_user(uidb64)
        if user is None:
            return Response(
                {'detail': 'User account not found.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Check OTP reset token first
        otp_record = PasswordResetOTP.objects.filter(
            user=user,
            reset_token=reset_token,
            is_verified=True,
            is_used=False,
            expires_at__gte=timezone.now(),
        ).first()

        # Fallback to default Django token generator if OTP record not found
        is_valid = False
        if otp_record:
            is_valid = True
        elif default_token_generator.check_token(user, reset_token):
            is_valid = True

        if not is_valid:
            return Response(
                {'detail': 'This password reset session is invalid or has expired. Please start over.'},
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

        if otp_record:
            otp_record.is_used = True
            otp_record.save(update_fields=['is_used'])

        # Send confirmation email (best-effort).
        try:
            email_sent = send_password_changed_email(user)
            if not email_sent:
                logger.warning('password_reset: password changed but confirmation email failed for user_id=%s', user.pk)
        except Exception as e:
            logger.warning('password_reset: error sending confirmation email for user_id=%s: %s', user.pk, e)

        # Create in-app system notification.
        try:
            from notifications.services import create_notification
            from notifications.models import NotificationCategory, NotificationPriority
            create_notification(
                recipient=user,
                title='Password Reset Successful',
                message='Your account password was successfully reset. If you did not request this change, please contact system support immediately.',
                category=NotificationCategory.SECURITY,
                priority=NotificationPriority.HIGH,
                action_route='/me/profile',
            )
        except Exception as e:
            logger.warning('password_reset: error creating system notification for user_id=%s: %s', user.pk, e)

        logger.info('password_reset: user_id=%s successfully reset password', user.pk)
        return Response({'detail': 'Your password has been reset successfully.'})


