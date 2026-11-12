"""Batch-scoped department authorizations and canonical workload projections."""
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
from defensys_backend.read_projection import read_memoize


@read_memoize
def operating_intake(term):
    """Only recorded normal continuation carries an intake into Capstone 2."""
    from academic_period_management.models import Semester, SemesterTransitionLog
    from .capstone_lifecycle import transition_kind
    if not term:
        return None
    if term.label == Semester.SECOND:
        return term
    if term.label != Semester.FIRST:
        return None
    log = SemesterTransitionLog.objects.filter(to_semester=term, operation='activation').select_related(
        'from_semester__school_year').order_by('-pk').first()
    if not log or transition_kind(log.from_semester, term) != 'continue':
        return None
    review = log.impact_snapshot.get('capstone_review', {})
    # During activation the validated preview is recorded before team writes.
    # Once committed, actual applied IDs are authoritative, including an empty list.
    included = log.impact_snapshot.get('applied_team_ids',
        [row['team_id'] for row in review.get('teams', []) if row.get('can_include')])
    return log.from_semester if review.get('kind') == 'continue' and included else None


def candidate_intake_id(team):
    from academic_period_management.models import Semester
    from .participation import intake_for
    if team.intake_semester_id:
        return team.intake_semester_id
    if not team.semester_id:
        return None
    if not team.pk and team.semester.label != Semester.SECOND:
        # An unsaved first-term candidate has no recorded continuation evidence.
        return None
    intake = intake_for(team)
    return intake.pk if intake else None


def effective_exception(adviser_id, *, team):
    intake = operating_intake(active_semester())
    if not intake or candidate_intake_id(team) != intake.pk:
        return None
    return AdviserCapacityException.objects.filter(adviser_id=adviser_id,
        intake_semester=intake, ended_at__isnull=True).first()


def capacity_for_intake(capacity, intake_id):
    """An older project's context cannot lend its approval to another intake."""
    if intake_id == capacity['intake_semester_id']:
        return capacity
    count = capacity['active_count']
    return {**capacity, 'intake_semester_id': intake_id, 'intake_label': None,
        'batch_active_count': None, 'other_batch_active_count': None,
        'phase': 'needs_review', 'effective_limit': MAX_ACTIVE_CAPSTONE_TEAMS,
        'can_assign': False, 'is_overloaded': count > MAX_ACTIVE_CAPSTONE_TEAMS,
        'exception_id': None, 'has_exception': False, 'exception_status': 'out_of_cycle'}


def _belongs_to_intake(team, intake_id):
    if team.intake_semester_id:
        return team.intake_semester_id == intake_id
    if team.semester_id == intake_id:
        return True
    # Workloads prefetch these rows; legacy continuation must not add queries.
    return any(row.semester_id == intake_id and row.project_version == team.project_version
        and not row.is_extended for row in team.term_participations.all())


def capacity_projections(adviser_ids, *, workloads=None):
    ids = list(adviser_ids)
    term = active_semester()
    intake = operating_intake(term)
    if workloads is None:
        workloads = active_teams_by_adviser(ids)
    exceptions = {row.adviser_id: row for row in AdviserCapacityException.objects.filter(
        adviser_id__in=ids, intake_semester=intake)} if intake else {}
    result = {}
    for adviser_id in ids:
        row = exceptions.get(adviser_id)
        effective = row if row and not row.ended_at else None
        limit = effective.approved_limit if effective else MAX_ACTIVE_CAPSTONE_TEAMS
        count = len(workloads.get(adviser_id, []))
        batch_count = sum(1 for team in workloads.get(adviser_id, [])
            if intake and _belongs_to_intake(team, intake.pk))
        result[adviser_id] = {'adviser_id': adviser_id, 'semester_id': term.pk if term else None,
            'intake_semester_id': intake.pk if intake else None,
            'operating_intake_semester_id': intake.pk if intake else None,
            'intake_label': intake.display_name if intake else None,
            'phase': ('capstone_1' if intake.pk == term.pk else 'capstone_2') if intake else 'needs_review',
            'active_count': count, 'standard_limit': MAX_ACTIVE_CAPSTONE_TEAMS,
            'batch_active_count': batch_count, 'other_batch_active_count': count - batch_count,
            'effective_limit': limit, 'can_assign': bool(intake and count < limit),
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
    previous_teams = {team.pk: team for team in StudentTeam.objects.filter(pk__in=existing_ids).select_related(
        'semester__school_year', 'intake_semester__school_year')}
    for index, (result, adviser_id, team_id) in enumerate(entries):
        if not adviser_id:
            continue
        existing = previous_teams.get(team_id)
        capacity = capacities[adviser_id]
        if existing:
            capacity = capacity_for_intake(capacity, candidate_intake_id(existing))
        result['adviser_capacity'] = {**capacity, 'projected_count': len(assigned[adviser_id])}
        if not result['ready']:
            continue
        already_counted = team_id is not None and team_id in assigned[adviser_id]
        if not already_counted and len(assigned[adviser_id]) >= capacity['effective_limit']:
            result['issues'].append(f"This adviser would exceed the limit of {capacity['effective_limit']} active Capstone teams in this import.")
            result['ready'] = False
            continue
        assigned[adviser_id].add(team_id if team_id else ('new', index))
        old_adviser = existing.adviser_id if existing else None
        if old_adviser and old_adviser != adviser_id and old_adviser in assigned:
            assigned[old_adviser].discard(team_id)
        result['adviser_capacity']['projected_count'] = len(assigned[adviser_id])


def exception_status(row):
    if not row.intake_semester_id:
        return 'needs_review'
    return (row.end_kind or 'legacy_ended') if row.ended_at else 'active'


def exception_values(row):
    return {'adviser_id': row.adviser_id, 'semester_id': row.semester_id,
        'intake_semester_id': row.intake_semester_id,
        'intake_label': row.intake_semester.display_name if row.intake_semester_id else None,
        'status': exception_status(row),
        'approved_limit': row.approved_limit, 'authorization': row.authorization,
        'reason': row.reason, 'reference': row.reference, 'created_by': row.created_by_id,
        'created_at': row.created_at.isoformat(), 'updated_by': row.updated_by_id,
        'updated_at': row.updated_at.isoformat(),
        'ended_at': row.ended_at.isoformat() if row.ended_at else None,
        'ended_by': row.ended_by_id, 'end_reason': row.end_reason, 'end_kind': row.end_kind}


def audit_exception(row, *, actor, action, before, reason):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action=f'adviser_capacity.{action}', target=row, actor=actor,
        old_values=before, new_values={**exception_values(row), 'scope': 'capstone',
            'active_count': capacity_projections([row.adviser_id])[row.adviser_id]['active_count']},
        reason=reason, strict=True)


class ExceptionWriteSerializer(serializers.Serializer):
    adviser_id = serializers.IntegerField(min_value=1)
    semester_id = serializers.IntegerField(min_value=1)
    intake_semester_id = serializers.IntegerField(min_value=1, required=False)
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
            intake_semester_id = serializers.IntegerField(min_value=1, required=False)
            reason = serializers.CharField(max_length=1000)
        validator = RevokeSerializer(data=data)
    else:
        validator = ExceptionWriteSerializer(data=data)
    validator.is_valid(raise_exception=True)
    values = validator.validated_data
    term = active_semester()
    if not term or values['semester_id'] != term.pk:
        raise serializers.ValidationError({'semester_id': 'Refresh and choose the active academic period.'})
    intake = operating_intake(term)
    if not intake or values.get('intake_semester_id', intake.pk) != intake.pk:
        raise serializers.ValidationError({'intake_semester_id': 'Refresh and choose the current Capstone batch.'})
    adviser = get_user_model().objects.select_for_update().filter(
        pk=values['adviser_id'], is_active=True, role__in=['faculty', 'admin']).first()
    if not adviser:
        raise serializers.ValidationError({'adviser_id': 'Choose an active faculty or admin adviser.'})
    row = AdviserCapacityException.objects.select_for_update().filter(adviser=adviser, intake_semester=intake).first()
    before = exception_values(row) if row else {'approved_limit': MAX_ACTIVE_CAPSTONE_TEAMS}
    if revoke:
        if not row or row.ended_at:
            raise serializers.ValidationError({'detail': 'There is no active exception to revoke.'})
        row.ended_at, row.ended_by, row.end_reason = timezone.now(), actor, values['reason']
        row.end_kind = 'revoked'
        action = 'revoked'
    else:
        action = 'renewed' if row and row.ended_at else 'updated' if row else 'created'
        row = row or AdviserCapacityException(adviser=adviser, semester=term, intake_semester=intake, created_by=actor)
        for key in ('approved_limit', 'authorization', 'reason', 'reference'):
            setattr(row, key, values[key])
        row.ended_at, row.ended_by, row.end_reason = None, None, ''
        row.end_kind = ''
    row.updated_by = actor
    row.full_clean()
    row.save()
    audit_exception(row, actor=actor, action=action, before=before, reason=values['reason'])
    return row


CYCLE_END_REASON = 'Capstone cycle ended; a new batch starts at the standard limit of four.'


def retire_exceptions(semester_ids, *, actor=None, preserve_intake_id=None):
    """Period locks serialize reset, assignment, and approval writes.

    Issuance may be two terms ago, so retirement cannot filter by issuance term.
    Only the validated activation service can preserve a continuing batch.
    """
    if not semester_ids:
        return
    rows = AdviserCapacityException.objects.select_for_update().filter(ended_at__isnull=True)
    if preserve_intake_id is not None:
        rows = rows.exclude(intake_semester_id=preserve_intake_id)
    for row in rows.order_by('adviser_id', 'pk'):
        before = exception_values(row)
        row.ended_at, row.ended_by = timezone.now(), actor
        row.end_reason = CYCLE_END_REASON
        row.end_kind = 'retired'
        row.updated_by = actor
        row.save()
        audit_exception(row, actor=actor, action='retired', before=before, reason=row.end_reason)
