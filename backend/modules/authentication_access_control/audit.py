import logging
import re

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework.exceptions import ValidationError

from .models import SystemAuditLog


logger = logging.getLogger(__name__)


def audit_track_marker(track):
    query = Q(pk__in=[])
    for side in ('old_values', 'new_values'):
        for key in ('entry_type', 'scope', 'track'):
            query |= Q(**{f'{side}__{key}': track})
    return query


def pit_audit_logs_for_year(queryset, year):
    marker = Q(pk__in=[])
    for side in ('old_values', 'new_values'):
        for key in ('year_level', 'team_year_level', 'pit_year_level'):
            marker |= Q(**{f'{side}__{key}': year})
    queryset = queryset.filter(audit_track_marker('pit') & marker)
    for side in ('old_values', 'new_values'):
        for key in ('entry_type', 'scope', 'track'):
            field = f'{side}__{key}'
            queryset = queryset.filter(Q(**{f'{field}__isnull': True}) | Q(**{field: 'pit'}))
        for key in ('year_level', 'team_year_level', 'pit_year_level'):
            field = f'{side}__{key}'
            queryset = queryset.filter(Q(**{f'{field}__isnull': True}) | Q(**{field: year}))
    return queryset


def filter_audit_logs(queryset, params, *, include_scope=True, include_status=True):
    """Use identical scopes and filters for the register, progress, and exports."""
    for key in ('category', 'action'):
        value = params.get(key, '').strip()
        if value:
            queryset = queryset.filter(**{key: value})
    review_status = params.get('review_status', '').strip()
    if include_status and review_status:
        statuses = [review_status]
        if review_status == SystemAuditLog.REVIEW_NEEDS_REVIEW:
            statuses += [SystemAuditLog.REVIEW_REQUIRES_REASON, SystemAuditLog.REVIEW_CAPTURED]
        queryset = queryset.filter(review_status__in=statuses)
    actor = params.get('actor', '').strip()
    if actor:
        queryset = queryset.filter(actor_id=actor)
    for key, lookup in (('start_date', 'gte'), ('end_date', 'lte')):
        value = parse_date(params.get(key, '').strip())
        if value:
            queryset = queryset.filter(**{f'created_at__date__{lookup}': value})
    if include_scope:
        track = params.get('track', '').strip().lower()
        if track in ('pit', 'capstone'):
            queryset = queryset.filter(audit_track_marker(track))
            if track == 'capstone':
                queryset = queryset.exclude(pk__in=queryset.filter(audit_track_marker('pit')).values('pk'))
        elif track == 'system':
            academic_ids = queryset.filter(audit_track_marker('pit') | audit_track_marker('capstone')).values('pk')
            queryset = queryset.exclude(pk__in=academic_ids)
        year = params.get('year_level', '').strip()
        if year:
            marker = Q(pk__in=[])
            for side in ('old_values', 'new_values'):
                for key in ('year_level', 'team_year_level', 'pit_year_level'):
                    marker |= Q(**{f'{side}__{key}': year})
            queryset = queryset.filter(marker)
    search = params.get('search', '').strip()
    if search:
        queryset = queryset.filter(
            Q(action__icontains=search) | Q(target_type__icontains=search)
            | Q(target_id__icontains=search) | Q(reason__icontains=search)
            | Q(actor__username__icontains=search) | Q(actor__first_name__icontains=search)
            | Q(actor__last_name__icontains=search) | Q(reviewed_by_name__icontains=search)
            | Q(reference_labels__icontains=search)
            | Q(old_values__icontains=search) | Q(new_values__icontains=search)
        )
    return queryset


@transaction.atomic
def review_audit_log(*, queryset, pk, reviewer, new_status, reason=''):
    """Serialize review decisions so retries cannot replace another reviewer's attribution."""
    from .models import SystemAuditReview
    from .scopes import is_admin_user

    # Scope first, lock only the audit row (nullable joined actors cannot be locked).
    log = SystemAuditLog.objects.select_for_update().get(pk__in=queryset.values('pk'), pk=pk)
    if new_status not in dict(SystemAuditLog.REVIEW_STATUS_CHOICES):
        raise ValidationError({'detail': 'Invalid review status.'})
    if log.review_status == new_status:
        return log
    if log.review_status == SystemAuditLog.REVIEW_REVIEWED and not reason:
        raise ValidationError({'detail': 'A reason is required to reopen a reviewed audit record.'})
    name = reviewer.get_full_name().strip() or reviewer.username
    role = 'admin' if is_admin_user(reviewer) else 'pit_lead'
    year = '' if role == 'admin' else (reviewer.pit_lead_year or '').strip()
    SystemAuditReview.objects.create(
        audit_log=log, reviewer=reviewer, reviewer_name=name, reviewer_role=role,
        reviewer_year=year, from_status=log.review_status, to_status=new_status, reason=reason,
    )
    log.review_status = new_status
    if new_status == SystemAuditLog.REVIEW_REVIEWED:
        log.reviewed_by = reviewer
        log.reviewed_at = timezone.now()
        log.reviewed_by_name = name
        log.reviewed_by_role = role
        log.reviewed_by_year = year
    log.save(update_fields=[
        'review_status', 'reviewed_by', 'reviewed_at', 'reviewed_by_name',
        'reviewed_by_role', 'reviewed_by_year',
    ])
    return log


AUDIT_EVENT_FIELDS = (
    'category',
    'action',
    'target_type',
    'target_id',
    'old_values',
    'new_values',
    'reason',
    'review_status',
)

PIT_SCOPE_METADATA_KEYS = (
    'entry_type',
    'scope',
    'track',
    'year_level',
    'team_year_level',
    'pit_year_level',
)


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


def audit_snapshot_fields(values):
    """Scope tags locate an event; they do not prove what happened to a record."""
    if not isinstance(values, dict):
        return {}
    scope_keys = set(PIT_SCOPE_METADATA_KEYS)
    return {key: value for key, value in values.items() if key not in scope_keys}


def audit_reason_required(action, old_values=None):
    """Creation needs no justification; changing saved data does."""
    if audit_snapshot_fields(old_values):
        return True
    words = set(re.split(r'[._\s]+', (action or '').lower()))
    if words & {'create', 'created', 'upload', 'uploaded', 'generate', 'generated', 'exchange'}:
        return False
    mutation_words = {
        'update', 'updated', 'edit', 'edited', 'delete', 'deleted',
        'remove', 'removed', 'change', 'changed', 'modify', 'modified',
        'restore', 'restored', 'reopen', 'reopened', 'publish', 'published',
        'finalize', 'finalized', 'complete', 'completed', 'completion',
        'switch', 'transition', 'reset', 'activate', 'deactivate',
        'approve', 'approved', 'reject', 'rejected', 'apply', 'applied',
        'archive', 'archived', 'lock', 'unlock', 'amendment', 'correction',
        'assign', 'assigned', 'reschedule', 'started',
    }
    return bool(words & mutation_words)


def audit_evidence(log):
    """Evidence completeness and human review are independent facts."""
    before = audit_snapshot_fields(log.old_values)
    after = audit_snapshot_fields(log.new_values)
    captured = bool(before or after)
    required = audit_reason_required(log.action, log.old_values)
    if not captured:
        summary = 'Before/after event data was not recorded.'
    elif before and after:
        changed = [key for key in dict.fromkeys([*before, *after])
                   if (key not in before or key not in after or before[key] != after[key])]
        summary = f'{len(changed)} changed field(s); before/after values recorded.'
    elif before:
        summary = f'{len(before)} field(s) recorded before the action.'
    else:
        summary = f'{len(after)} field(s) recorded after the action.'
    return {
        'status': 'captured' if captured else 'incomplete',
        'label': 'Evidence captured' if captured else 'Event details incomplete',
        'summary': summary,
        'reason_required': required,
    }


def review_status_for(reason='', *, action='', old_values=None, new_values=None):
    if audit_reason_required(action, old_values) and not (reason or '').strip():
        return SystemAuditLog.REVIEW_REQUIRES_REASON
    if audit_snapshot_fields(old_values) or audit_snapshot_fields(new_values):
        return SystemAuditLog.REVIEW_CAPTURED
    return SystemAuditLog.REVIEW_NEEDS_REVIEW


def audit_scope_metadata(*, scope='', track='', entry_type='', team=None, year_level=''):
    resolved_scope = (scope or '').strip()
    resolved_track = (track or resolved_scope).strip()
    resolved_entry_type = (entry_type or resolved_track).strip()
    resolved_year = (year_level or getattr(team, 'year_level', '') or '').strip()
    metadata = {
        'scope': resolved_scope,
        'track': resolved_track,
        'entry_type': resolved_entry_type,
    }
    if getattr(team, 'pk', None):
        metadata['team_id'] = team.pk
        metadata['team_name'] = getattr(team, 'name', '')
    if resolved_year:
        metadata['year_level'] = resolved_year
        metadata['team_year_level'] = resolved_year
        if resolved_scope == 'pit' or resolved_track == 'pit' or resolved_entry_type == 'pit':
            metadata['pit_year_level'] = resolved_year
    return {key: value for key, value in metadata.items() if value not in ('', None)}


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
    strict=False,
):
    actor = actor or actor_from_request(request)
    if reason is not None and not isinstance(reason, str):
        raise ValidationError({'reason': 'A reason must be text.'})
    reason = (reason or '').strip()
    target_type = target_type or target.__class__.__name__
    target_id = str(target_id if target_id is not None else getattr(target, 'pk', '') or '')
    try:
        from .audit_references import capture_audit_references

        return SystemAuditLog.objects.create(
            actor=actor if getattr(actor, 'is_authenticated', False) else None,
            category=category,
            action=action,
            target_type=target_type,
            target_id=target_id,
            old_values=old_values or {},
            new_values=new_values or {},
            reference_labels=capture_audit_references(
                target=target, target_type=target_type, target_id=target_id,
                category=category, action=action,
                old_values=old_values or {}, new_values=new_values or {},
            ),
            reason=reason,
            review_status=review_status or review_status_for(
                reason, action=action, old_values=old_values, new_values=new_values,
            ),
            ip_address=request_ip(request),
            user_agent=request_user_agent(request),
        )
    except Exception:
        logger.exception('Failed to write high-impact audit log.')
        if strict:
            from rest_framework.exceptions import APIException
            raise APIException('The audit record could not be saved. No change was applied; please retry.')
        return None
