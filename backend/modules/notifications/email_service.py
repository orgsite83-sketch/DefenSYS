"""
Centralized email helpers for DefenSYS.

All outbound emails go through these helpers so behaviour (logging,
error handling, template rendering) stays consistent.
"""

import logging

from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
from django.utils.html import strip_tags

logger = logging.getLogger(__name__)


def _send(subject: str, html_body: str, recipient_email: str) -> bool:
    """Send an email, returning True on success."""
    if not recipient_email:
        logger.warning('email_service: skipped — no recipient email.')
        return False

    plain_body = strip_tags(html_body)
    try:
        send_mail(
            subject=subject,
            message=plain_body,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[recipient_email],
            html_message=html_body,
            fail_silently=False,
        )
        logger.info('email_service: sent "%s" to %s', subject, recipient_email)
        return True
    except Exception:
        logger.exception('email_service: failed to send "%s" to %s', subject, recipient_email)
        return False


def send_password_changed_email(user) -> bool:
    """Notify the user that their password was changed."""
    html = render_to_string('emails/password_changed.html', {
        'user': user,
        'app_name': 'DefenSYS',
    })
    return _send(
        subject='DefenSYS — Your password was changed',
        html_body=html,
        recipient_email=user.email,
    )


def send_password_reset_email(user, reset_url: str) -> bool:
    """Send a password-reset link to the user."""
    html = render_to_string('emails/password_reset_link.html', {
        'user': user,
        'reset_url': reset_url,
        'app_name': 'DefenSYS',
        'expiry_minutes': settings.PASSWORD_RESET_TIMEOUT // 60,
    })
    return _send(
        subject='DefenSYS — Password Reset Request',
        html_body=html,
        recipient_email=user.email,
    )


def send_password_reset_otp_email(user, otp_code: str) -> bool:
    """Send a 6-digit password reset verification code to the user."""
    expiry_seconds = getattr(settings, 'PASSWORD_RESET_OTP_TIMEOUT', 600)
    html = render_to_string('emails/password_reset_otp.html', {
        'user': user,
        'otp_code': otp_code,
        'app_name': 'DefenSYS',
        'expiry_minutes': max(1, expiry_seconds // 60),
    })
    return _send(
        subject='DefenSYS — Password Reset Verification Code',
        html_body=html,
        recipient_email=user.email,
    )



def send_admin_password_reset_email(user) -> bool:
    """Notify the user that an admin reset their password."""
    html = render_to_string('emails/admin_password_reset.html', {
        'user': user,
        'app_name': 'DefenSYS',
    })
    return _send(
        subject='DefenSYS — Your password was reset by an administrator',
        html_body=html,
        recipient_email=user.email,
    )
