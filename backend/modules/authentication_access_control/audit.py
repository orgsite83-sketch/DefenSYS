import logging

from .models import SystemAuditLog


logger = logging.getLogger(__name__)


def actor_from_request(request):
    if request is None:
        return None
    user = getattr(request, 'user', None)
    if getattr(user, 'is_authenticated', False):
        return user
    return None


def request_ip(request):
    if request is None:
        return None
    forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if forwarded_for:
        return forwarded_for.split(',')[0].strip() or None
    return request.META.get('REMOTE_ADDR') or None


def request_user_agent(request):
    if request is None:
        return ''
    return request.META.get('HTTP_USER_AGENT', '')


def review_status_for(reason=''):
    return (
        SystemAuditLog.REVIEW_CAPTURED
        if (reason or '').strip()
        else SystemAuditLog.REVIEW_REQUIRES_REASON
    )


def log_high_impact_action(
    *,
    category,
    action,
    target,
    target_type=None,
    target_id=None,
    old_values=None,
    new_values=None,
    reason='',
    request=None,
    actor=None,
    review_status=None,
):
    actor = actor or actor_from_request(request)
    reason = (reason or '').strip()
    target_type = target_type or target.__class__.__name__
    target_id = str(target_id if target_id is not None else getattr(target, 'pk', '') or '')
    try:
        return SystemAuditLog.objects.create(
            actor=actor if getattr(actor, 'is_authenticated', False) else None,
            category=category,
            action=action,
            target_type=target_type,
            target_id=target_id,
            old_values=old_values or {},
            new_values=new_values or {},
            reason=reason,
            review_status=review_status or review_status_for(reason),
            ip_address=request_ip(request),
            user_agent=request_user_agent(request),
        )
    except Exception:
        logger.exception('Failed to write high-impact audit log.')
        return None
