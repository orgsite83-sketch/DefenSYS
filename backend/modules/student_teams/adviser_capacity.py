"""Semester-scoped department authorizations and canonical workload projections."""
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied

from academic_period_management.services import active_semester
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from .models import AdviserCapacityException
from .adviser_assignments import MAX_ACTIVE_CAPSTONE_TEAMS, active_teams_by_adviser


def effective_exception(adviser_id):
    return AdviserCapacityException.objects.filter(adviser_id=adviser_id,
        semester__is_active=True, ended_at__isnull=True).first()


def capacity_projections(adviser_ids, *, workloads=None):
    ids = list(adviser_ids)
    term = active_semester()
    if workloads is None:
        workloads = active_teams_by_adviser(ids)
    exceptions = {row.adviser_id: row for row in AdviserCapacityException.objects.filter(
        adviser_id__in=ids, semester=term)} if term else {}
    result = {}
    for adviser_id in ids:
        row = exceptions.get(adviser_id)
        effective = row if row and not row.ended_at else None
        limit = effective.approved_limit if effective else MAX_ACTIVE_CAPSTONE_TEAMS
        count = len(workloads.get(adviser_id, []))
        result[adviser_id] = {'adviser_id': adviser_id, 'semester_id': term.pk if term else None,
            'active_count': count, 'standard_limit': MAX_ACTIVE_CAPSTONE_TEAMS,
            'effective_limit': limit, 'can_assign': bool(term and count < limit),
            'is_overloaded': count > limit, 'exception_id': row.pk if row else None,
            'has_exception': effective is not None,
            'exception_status': 'active' if effective else 'ended' if row else 'none'}
    return result


def annotate_import_capacity(entries):
    """Reserve places across ready rows without writing or trusting a preview later.

    Entries are (public result, adviser ID, existing team ID). Accepted transfers
    release their source place in the same deterministic order as import writes.
    """
    from .models import StudentTeam
    ids = {adviser_id for _, adviser_id, _ in entries if adviser_id}
    if not ids:
        return
    workloads = active_teams_by_adviser(ids)
    capacities = capacity_projections(ids, workloads=workloads)
    assigned = {pk: {team.pk for team in teams} for pk, teams in workloads.items()}
    existing_ids = {pk for _, _, pk in entries if pk}
    previous = dict(StudentTeam.objects.filter(pk__in=existing_ids).values_list('pk', 'adviser_id'))
    for index, (result, adviser_id, team_id) in enumerate(entries):
        if not adviser_id:
            continue
        capacity = capacities[adviser_id]
        result['adviser_capacity'] = {**capacity, 'projected_count': len(assigned[adviser_id])}
        if not result['ready']:
            continue
        already_counted = team_id is not None and team_id in assigned[adviser_id]
        if not already_counted and len(assigned[adviser_id]) >= capacity['effective_limit']:
            result['issues'].append(f"This adviser would exceed the limit of {capacity['effective_limit']} active Capstone teams in this import.")
            result['ready'] = False
            continue
        assigned[adviser_id].add(team_id if team_id else ('new', index))
        old_adviser = previous.get(team_id)
        if old_adviser and old_adviser != adviser_id and old_adviser in assigned:
            assigned[old_adviser].discard(team_id)
        result['adviser_capacity']['projected_count'] = len(assigned[adviser_id])


def exception_values(row):
    return {'adviser_id': row.adviser_id, 'semester_id': row.semester_id,
        'approved_limit': row.approved_limit, 'authorization': row.authorization,
        'reason': row.reason, 'reference': row.reference, 'created_by': row.created_by_id,
        'created_at': row.created_at.isoformat(), 'updated_by': row.updated_by_id,
        'updated_at': row.updated_at.isoformat(),
        'ended_at': row.ended_at.isoformat() if row.ended_at else None,
        'ended_by': row.ended_by_id, 'end_reason': row.end_reason}


def audit_exception(row, *, actor, action, before, reason):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action=f'adviser_capacity.{action}', target=row, actor=actor,
        old_values=before, new_values={**exception_values(row), 'scope': 'capstone',
            'active_count': capacity_projections([row.adviser_id])[row.adviser_id]['active_count']},
        reason=reason, strict=True)


class ExceptionWriteSerializer(serializers.Serializer):
    adviser_id = serializers.IntegerField(min_value=1)
    semester_id = serializers.IntegerField(min_value=1)
    approved_limit = serializers.IntegerField(min_value=5, max_value=32767)
    authorization = serializers.CharField(max_length=500)
    reason = serializers.CharField(max_length=1000)
    reference = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')


@transaction.atomic
def save_exception(actor, data, *, revoke=False):
    if not actor.is_authenticated or not (actor.is_superuser or actor.role == 'admin'):
        raise PermissionDenied('Only administrators can manage adviser limits.')
    from defense.scheduler.capstone_planning import lock_calendar_resources
    lock_calendar_resources()
    if revoke:
        class RevokeSerializer(serializers.Serializer):
            adviser_id = serializers.IntegerField(min_value=1)
            semester_id = serializers.IntegerField(min_value=1)
            reason = serializers.CharField(max_length=1000)
        validator = RevokeSerializer(data=data)
    else:
        validator = ExceptionWriteSerializer(data=data)
    validator.is_valid(raise_exception=True)
    values = validator.validated_data
    term = active_semester()
    if not term or values['semester_id'] != term.pk:
        raise serializers.ValidationError({'semester_id': 'Refresh and choose the active academic period.'})
    adviser = get_user_model().objects.select_for_update().filter(
        pk=values['adviser_id'], is_active=True, role__in=['faculty', 'admin']).first()
    if not adviser:
        raise serializers.ValidationError({'adviser_id': 'Choose an active faculty or admin adviser.'})
    row = AdviserCapacityException.objects.select_for_update().filter(adviser=adviser, semester=term).first()
    before = exception_values(row) if row else {'approved_limit': MAX_ACTIVE_CAPSTONE_TEAMS}
    if revoke:
        if not row or row.ended_at:
            raise serializers.ValidationError({'detail': 'There is no active exception to revoke.'})
        row.ended_at, row.ended_by, row.end_reason = timezone.now(), actor, values['reason']
        action = 'revoked'
    else:
        action = 'renewed' if row and row.ended_at else 'updated' if row else 'created'
        row = row or AdviserCapacityException(adviser=adviser, semester=term, created_by=actor)
        for key in ('approved_limit', 'authorization', 'reason', 'reference'):
            setattr(row, key, values[key])
        row.ended_at, row.ended_by, row.end_reason = None, None, ''
    row.updated_by = actor
    row.full_clean()
    row.save()
    audit_exception(row, actor=actor, action=action, before=before, reason=values['reason'])
    return row


def retire_exceptions(semester_ids, *, actor=None):
    """Called under period locks, including direct model activation/deactivation."""
    for row in AdviserCapacityException.objects.select_for_update().filter(
            semester_id__in=semester_ids, ended_at__isnull=True).order_by('adviser_id'):
        before = exception_values(row)
        row.ended_at, row.ended_by = timezone.now(), actor
        row.end_reason = 'Academic period ended; additional assignments require fresh authorization.'
        row.updated_by = actor
        row.save()
        audit_exception(row, actor=actor, action='retired', before=before, reason=row.end_reason)
