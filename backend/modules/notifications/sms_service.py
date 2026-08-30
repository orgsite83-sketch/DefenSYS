"""
Centralized SMS helpers for DefenSYS.

Supports multiple SMS backends:
  - 'console': Prints the SMS directly to terminal/logs (default for zero-cost dev/demo).
  - 'android_gateway': Relays SMS via a networked Android Phone running an SMS Gateway app (e.g. Android SMS Gateway, Textbee).
  - 'semaphore': Sends SMS via Semaphore Philippines API.
  - 'twilio': Sends SMS via Twilio Programmable SMS API.
"""

import logging
import re
import requests
from django.conf import settings

logger = logging.getLogger(__name__)


def clean_phone_number(phone: str) -> str:
    """Strip whitespace, dashes, and parentheticals from phone number."""
    if not phone:
        return ''
    cleaned = re.sub(r'[\s\-\(\)]+', '', phone.strip())
    return cleaned


def mask_phone_number(phone: str) -> str:
    """
    Mask phone number for safe UI display (e.g., '+63 917 *** *567' or '0917 *** *567').
    """
    cleaned = clean_phone_number(phone)
    if not cleaned:
        return ''
    if len(cleaned) <= 4:
        return '*' * len(cleaned)
    if len(cleaned) >= 10:
        # e.g., 09171234567 -> 0917 *** *567
        prefix = cleaned[:4]
        suffix = cleaned[-3:]
        return f'{prefix} *** *{suffix}'
    # Shorter fallback
    return cleaned[:2] + ('*' * (len(cleaned) - 4)) + cleaned[-2:]


def _send_via_console(recipient_phone: str, message: str) -> bool:
    """Log the SMS to console/logger."""
    logger.info(
        '\n==================================================\n'
        '[SMS CONSOLE DISPATCH]\n'
        'Recipient: %s\n'
        'Message:   %s\n'
        '==================================================',
        recipient_phone,
        message,
    )
    return True


def _send_via_android_gateway(recipient_phone: str, message: str) -> bool:
    """
    Send SMS via an Android device running a local/cloud SMS Gateway app.
    Supports Android SMS Gateway (capcom6), Textbee, and generic webhook endpoints.
    """
    gateway_url = getattr(settings, 'SMS_GATEWAY_URL', '').strip()
    if not gateway_url:
        logger.error('sms_service: SMS_GATEWAY_URL is not configured.')
        return False

    if not gateway_url.startswith('http://') and not gateway_url.startswith('https://'):
        gateway_url = f'http://{gateway_url}'

    # If base url given (e.g. http://192.168.1.150:8080), append /message
    if not (gateway_url.endswith('/message') or gateway_url.endswith('/api/v1/sms') or gateway_url.endswith('/send')):
        gateway_url = f'{gateway_url.rstrip("/")}/message'

    username = getattr(settings, 'SMS_GATEWAY_USERNAME', '').strip()
    password = getattr(settings, 'SMS_GATEWAY_PASSWORD', '').strip()
    api_key = getattr(settings, 'SMS_GATEWAY_API_KEY', '').strip()

    headers = {'Content-Type': 'application/json'}
    if api_key:
        headers['Authorization'] = f'Bearer {api_key}'
        headers['X-API-Key'] = api_key

    auth = (username, password) if (username and password) else None

    # Payload structured to support Capcom6 Android SMS Gateway & Textbee
    payload = {
        'message': message,
        'phoneNumbers': [recipient_phone],
        'to': recipient_phone,
        'phone': recipient_phone,
        'phoneNumber': recipient_phone,
        'text': message,
    }

    try:
        response = requests.post(gateway_url, json=payload, headers=headers, auth=auth, timeout=10)
        if response.status_code in (200, 201, 202):
            logger.info('sms_service: Android Gateway successfully dispatched SMS to %s', recipient_phone)
            return True
        logger.error(
            'sms_service: Android Gateway responded with status %s: %s',
            response.status_code,
            response.text,
        )
        return False
    except Exception:
        logger.exception('sms_service: Failed to connect to Android SMS Gateway at %s', gateway_url)
        return False


def _send_via_semaphore(recipient_phone: str, message: str) -> bool:
    """Send SMS via Semaphore API (Philippines)."""
    api_key = getattr(settings, 'SEMAPHORE_API_KEY', '').strip()
    if not api_key:
        logger.error('sms_service: SEMAPHORE_API_KEY is not configured.')
        return False

    sender_name = getattr(settings, 'SEMAPHORE_SENDER_NAME', 'DefenSYS').strip()
    payload = {
        'apikey': api_key,
        'number': recipient_phone,
        'message': message,
        'sendername': sender_name,
    }

    try:
        response = requests.post('https://api.semaphore.co/api/v4/messages', data=payload, timeout=10)
        if response.status_code == 200:
            logger.info('sms_service: Semaphore dispatched SMS to %s', recipient_phone)
            return True
        logger.error('sms_service: Semaphore API error %s: %s', response.status_code, response.text)
        return False
    except Exception:
        logger.exception('sms_service: Failed to send SMS via Semaphore to %s', recipient_phone)
        return False


def _send_via_twilio(recipient_phone: str, message: str) -> bool:
    """Send SMS via Twilio REST API."""
    account_sid = getattr(settings, 'TWILIO_ACCOUNT_SID', '').strip()
    auth_token = getattr(settings, 'TWILIO_AUTH_TOKEN', '').strip()
    from_number = getattr(settings, 'TWILIO_FROM_NUMBER', '').strip()

    if not (account_sid and auth_token and from_number):
        logger.error('sms_service: Twilio credentials (SID, Token, From) are not fully configured.')
        return False

    url = f'https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json'
    data = {
        'From': from_number,
        'To': recipient_phone,
        'Body': message,
    }

    try:
        response = requests.post(url, data=data, auth=(account_sid, auth_token), timeout=10)
        if response.status_code in (200, 201):
            logger.info('sms_service: Twilio dispatched SMS to %s', recipient_phone)
            return True
        logger.error('sms_service: Twilio error %s: %s', response.status_code, response.text)
        return False
    except Exception:
        logger.exception('sms_service: Failed to send SMS via Twilio to %s', recipient_phone)
        return False


def send_sms(recipient_phone: str, message: str) -> bool:
    """
    Send an SMS message using the configured SMS_BACKEND.
    Returns True on success, False otherwise.
    """
    cleaned_phone = clean_phone_number(recipient_phone)
    if not cleaned_phone:
        logger.warning('sms_service: skipped — empty recipient phone number.')
        return False

    backend = getattr(settings, 'SMS_BACKEND', 'console').lower().strip()

    if backend == 'android_gateway':
        return _send_via_android_gateway(cleaned_phone, message)
    elif backend == 'semaphore':
        return _send_via_semaphore(cleaned_phone, message)
    elif backend == 'twilio':
        return _send_via_twilio(cleaned_phone, message)
    else:
        # Default console mode
        return _send_via_console(cleaned_phone, message)


def send_password_reset_otp_sms(user, otp_code: str) -> bool:
    """
    Send a 6-digit password reset verification code to the user via SMS.
    """
    phone = getattr(user, 'phone_number', '') or ''
    if not phone:
        logger.warning('sms_service: User %s (ID %s) has no phone number on record.', user.username, user.pk)
        return False

    expiry_seconds = getattr(settings, 'PASSWORD_RESET_OTP_TIMEOUT', 600)
    expiry_mins = max(1, expiry_seconds // 60)
    message = (
        f'DefenSYS: Your password reset verification code is {otp_code}. '
        f'Valid for {expiry_mins} mins. Do not share this code with anyone.'
    )
    return send_sms(phone, message)
