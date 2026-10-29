from django.db import connection, transaction
from django.db.models import Count, Q
from hashlib import sha256
import json
from rest_framework.exceptions import ValidationError

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam
from .models import Semester, SemesterTransitionLog


def active_semester():
    """Single source of truth for the currently active semester."""
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def _lock_period_state():
    # A row lock alone cannot serialize two first activations when no period
    # exists yet. The transaction-scoped lock also covers that empty-table case.
    if connection.vendor == 'postgresql':
        with connection.cursor() as cursor:
            cursor.execute('SELECT pg_advisory_xact_lock(%s)', [741912004])
    list(Semester.objects.select_for_update().order_by('pk'))


def build_semester_transition_preview(target_semester):
    current_semester = (
        Semester.objects.select_related('school_year').filter(is_active=True).first()
    )
    if target_semester.pk is not None:
        target_semester = Semester.objects.select_related('school_year').get(pk=target_semester.pk)

    if current_semester and current_semester.pk == target_semester.pk:
        return {
            'current_semester': _semester_summary(current_semester),
            'target_semester': _semester_summary(target_semester),
            'impact_counts': {},
            'effects': [],
            'issues': [],
            'blocking_reasons': [],
            'can_switch': True,
        }

    impact_counts = _impact_counts(current_semester)
    effects = _transition_effects(current_semester, impact_counts)
    issues = _transition_issues(current_semester, impact_counts)

    from student_teams.capstone_lifecycle import build_capstone_review
    review = build_capstone_review(current_semester, target_semester)
    if review['kind'] == 'exceptional' and review['total']:
        issues.append({'key': 'exceptional_transition', 'blocking': True,
            'message': 'This is not a consecutive regular-term transition. No automatic team continuation will be applied.',
            'action_label': 'Review teams', 'route': '/admin/student-teams'})
    if review['counts']['needs_review']:
        issues.append({'key': 'capstone_unresolved', 'blocking': True,
            'count': review['counts']['needs_review'],
            'message': 'Capstone teams still have unresolved grading, clearance, or cohort records.',
            'action_label': 'Review grades', 'route': '/admin/grade-center'})
    blocking_reasons = [issue['message'] for issue in issues if issue.get('blocking')]
    revision = sha256(json.dumps({'capstone': review['revision'], 'counts': impact_counts,
        'effects': effects, 'issues': issues}, sort_keys=True).encode()).hexdigest()
    return {
        'current_semester': _semester_summary(current_semester),
        'target_semester': _semester_summary(target_semester),
        'impact_counts': impact_counts,
        'effects': effects,
        'issues': issues,
        'blocking_reasons': blocking_reasons,
        'can_switch': not blocking_reasons,
        'capstone_review': review,
        'preview_revision': revision,
    }


@transaction.atomic
def switch_active_semester(target_semester, user, force=False, reason='', *,
                           preview_revision='', request_id=None):
    reason = (reason or '').strip()
    if not (getattr(user, 'is_superuser', False) or getattr(user, 'role', None) == 'admin'):
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied('Only an administrator can activate a semester.')
    if request_id and (not isinstance(request_id, str) or len(request_id) > 64):
        raise ValidationError({'request_id': 'Use a request identity up to 64 characters.'})
    # All activation and enrollment paths lock periods in the same order.
    _lock_period_state()
    if request_id:
        previous = SemesterTransitionLog.objects.filter(request_id=request_id).first()
        if previous:
            if previous.operation != 'activation' or previous.to_semester_id != target_semester.pk or previous.changed_by_id != user.pk:
                raise ValidationError('This request identity has already been used for another transition.')
            if previous.reason != reason or previous.forced != bool(force):
                raise ValidationError('This request has already completed with different decisions. Refresh the period before starting another review.')
            return previous.impact_snapshot, previous
    source = active_semester()
    if source and source.pk == target_semester.pk:
        if preview_revision:
            raise ValidationError({'code': 'stale_preview', 'detail': 'This semester is already active. Refresh the current roster.'})
        return build_semester_transition_preview(target_semester), None
    from .calendar import validate_calendar
    target_semester.refresh_from_db()
    validate_calendar(target_semester.starts_on, target_semester.ends_on)
    source_teams = StudentTeam.objects.filter(semester=source)
    from django.contrib.auth import get_user_model
    from student_teams.models import TeamMembership
    ids = set(source_teams.values_list('leader_id', flat=True)) | set(TeamMembership.objects.filter(team__in=source_teams).values_list('student_id', flat=True))
    list(get_user_model().objects.select_for_update().filter(pk__in=ids).order_by('pk'))
    from user_management.academic_records.models import StudentAcademicRecord
    list(StudentAcademicRecord.objects.select_for_update().filter(student_id__in=ids,
        semester_id__in=[source.pk, target_semester.pk] if source else [target_semester.pk]).order_by('pk'))
    list(source_teams.select_for_update().order_by('pk'))
    list(TeamGrade.all_objects.select_for_update().filter(team__in=source_teams).order_by('pk'))
    preview = build_semester_transition_preview(target_semester)

    review = preview.get('capstone_review', {})
    if (review.get('requires_review') or preview_revision) and preview_revision != preview.get('preview_revision'):
        raise ValidationError({'detail': 'Review the current semester transition before confirming. The preview may have changed.',
                               'preview': preview, 'code': 'stale_preview'})

    if preview['blocking_reasons']:
        if not force:
            raise ValidationError({
                'detail': 'Resolve unfinished semester workflows before switching, or use a forced override.',
                'preview': preview,
            })
        if not reason:
            raise ValidationError({
                'reason': 'A reason is required when forcing an active semester switch.',
                'preview': preview,
            })

    with transaction.atomic():
        target = Semester.objects.select_for_update().select_related('school_year').get(
            pk=target_semester.pk,
        )
        current = (
            Semester.objects.select_for_update()
            .select_related('school_year')
            .filter(is_active=True)
            .first()
        )

        if current and current.pk == target.pk:
            return preview, None

        from .capstone_mode import normalize_capstone_flags
        target.is_active = True
        capstone_fields = normalize_capstone_flags(target)
        target.save(update_fields=['is_active'] + capstone_fields)
        log = SemesterTransitionLog.objects.create(
            request_id=request_id or None,
            preview_revision=preview.get('preview_revision', ''),
            from_semester=current,
            to_semester=target,
            changed_by=user if getattr(user, 'is_authenticated', False) else None,
            forced=bool(force),
            reason=reason,
            impact_snapshot=preview,
        )
        from student_teams.capstone_lifecycle import apply_capstone_transition
        applied = apply_capstone_transition(current, target, review, actor=user, log=log)
        log.impact_snapshot = {**preview, 'applied_team_ids': applied}
        log.save(update_fields=['impact_snapshot'])
        from repository.section_concepts.continuation import materialize_section
        materialized = set()
        for team in StudentTeam.objects.filter(pk__in=applied).order_by('pk'):
            key = (team.semester_id, team.section, team.year_level)
            if key not in materialized:
                materialize_section(team)
                materialized.add(key)
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
            action='semester.active_switch',
            target=target,
            target_type='Semester',
            target_id=target.pk,
            actor=user,
            old_values={
                'active_semester_id': current.pk if current else None,
                'active_semester': current.display_name if current else None,
            },
            new_values={
                'active_semester_id': target.pk,
                'active_semester': target.display_name,
                'forced': bool(force),
            },
            reason=reason,
            strict=True,
        )
        # Availability already rejects submissions for inactive semesters. Keep
        # saved component settings intact and refresh connected forms on commit.
        from realtime.broadcast import notify_capstone_evaluation_flags
        for semester in (current, target):
            if semester:
                transaction.on_commit(lambda semester=semester: notify_capstone_evaluation_flags(semester))

    return log.impact_snapshot, log


def proposed_semester(school_year, *, label, starts_on, ends_on, **_ignored):
    from .capstone_mode import default_capstone_flags_for_label
    creation, phase = default_capstone_flags_for_label(label)
    return Semester(school_year=school_year, label=label, starts_on=starts_on, ends_on=ends_on,
                    capstone_program_phase=phase, capstone_team_creation_enabled=creation)


@transaction.atomic
def create_semester(school_year, user, *, label, starts_on, ends_on, set_active=False,
                    force=False, reason='', preview_revision='', request_id=None):
    """Create and optionally activate together through the canonical transition."""
    from .calendar import validate_calendar
    from .models import SchoolYear
    from rest_framework.exceptions import PermissionDenied
    if not (user.is_superuser or user.role == 'admin'):
        raise PermissionDenied('Only an administrator can create a semester.')
    validate_calendar(starts_on, ends_on)
    _lock_period_state()
    SchoolYear.objects.select_for_update().get(pk=school_year.pk)
    identity = {'school_year_id': school_year.pk, 'label': label,
                'starts_on': starts_on.isoformat(), 'ends_on': ends_on.isoformat()}
    if set_active and request_id:
        previous = SemesterTransitionLog.objects.filter(request_id=request_id).select_related('to_semester').first()
        if previous:
            if (previous.changed_by_id != user.pk or previous.operation != 'activation'
                    or previous.impact_snapshot.get('created_term') != identity
                    or previous.forced != force or previous.reason != reason.strip()
                   ):
                raise ValidationError('This request identity has already been used for another operation.')
            if not previous.to_semester.is_active:
                raise ValidationError({'code': 'stale_creation',
                    'detail': 'This term was already created, and another semester is now active. Refresh academic periods.'})
            return previous.to_semester
    if Semester.objects.filter(school_year=school_year, label=label).exists():
        raise ValidationError({'label': 'This semester already exists for the selected school year.'})
    target = proposed_semester(school_year, label=label, starts_on=starts_on, ends_on=ends_on)
    if set_active:
        preview = build_semester_transition_preview(target)
        if active_semester() and preview_revision != preview['preview_revision']:
            raise ValidationError({'code': 'stale_preview', 'detail': 'Review the current semester transition before confirming.', 'preview': preview})
    target.save()
    if set_active:
        _preview, log = switch_active_semester(target, user, force=force, reason=reason,
            preview_revision=preview['preview_revision'], request_id=request_id)
        if log:
            log.impact_snapshot = {**log.impact_snapshot, 'created_term': identity}
            log.save(update_fields=['impact_snapshot'])
        target.refresh_from_db()
    return target


def _impact_counts(current_semester):
    if current_semester is None:
        return {
            'active_teams': 0,
            'capstone_teams': 0,
            'pit_teams': 0,
            'open_schedules': 0,
            'pending_grades': 0,
            'capstone_peer_evaluation_enabled': 0,
            'capstone_adviser_grading_enabled': 0,
            'pit_peer_grading_windows': 0,
            'incomplete_official_workflows': 0,
            'open_archive_queues': 0,
        }

    scheduled_events = DefenseSchedule.objects.filter(
        semester=current_semester,
        scope=DefenseSchedule.SCOPE_PIT,
        status=DefenseSchedule.STATUS_SCHEDULED,
    ).values_list('event_name', flat=True)
    pit_grade_config_ids = TeamGrade.objects.filter(
        semester=current_semester,
        scope=TeamGrade.SCOPE_PIT,
        pit_event_config__isnull=False,
    ).values_list('pit_event_config_id', flat=True)

    incomplete_official_workflows = PitEventGradingConfig.objects.filter(
        semester=current_semester,
        is_officially_complete=False,
    ).filter(
        Q(id__in=pit_grade_config_ids) | Q(event_name__in=scheduled_events),
    ).distinct().count()

    team_counts = StudentTeam.objects.filter(semester=current_semester).aggregate(
        active_teams=Count('pk'),
        capstone_teams=Count('pk', filter=Q(level__icontains='Capstone')),
        pit_teams=Count('pk', filter=Q(level__icontains='PIT')),
    )
    return {
        **team_counts,
        'open_schedules': DefenseSchedule.objects.filter(
            semester=current_semester,
            status=DefenseSchedule.STATUS_SCHEDULED,
        ).count(),
        'pending_grades': TeamGrade.objects.filter(
            semester=current_semester,
            status__in=[
                TeamGrade.STATUS_PENDING,
                TeamGrade.STATUS_AWAITING_PEERS,
            ],
        ).count(),
        'capstone_peer_evaluation_enabled': int(
            current_semester.capstone_peer_evaluation_enabled,
        ),
        'capstone_adviser_grading_enabled': int(
            current_semester.capstone_adviser_grading_enabled,
        ),
        'pit_peer_grading_windows': PitEventGradingConfig.objects.filter(
            semester=current_semester,
            peer_grading_enabled=True,
        ).count(),
        'incomplete_official_workflows': incomplete_official_workflows,
        'open_archive_queues': 0,
    }


def _transition_effects(current_semester, counts):
    if current_semester is None:
        return []

    effects = []
    pit_count = counts['pit_teams']
    if pit_count:
        noun = 'team' if pit_count == 1 else 'teams'
        effects.append({'key': 'pit_teams', 'count': pit_count,
            'message': f'This semester has {pit_count} PIT {noun}. PIT starts fresh next semester.'})
    if counts['capstone_teams'] and (counts['capstone_peer_evaluation_enabled']
            or counts['capstone_adviser_grading_enabled']):
        effects.append({'key': 'capstone_evaluation_closure',
            'message': 'Peer and adviser submissions close automatically for the outgoing semester.'})
    return effects


def _transition_issues(current_semester, counts):
    if current_semester is None:
        return []

    semester_id = current_semester.id
    issues = []

    _append_count_issue(
        issues,
        key='open_schedules',
        count=counts['open_schedules'],
        blocking=True,
        message='scheduled defenses are not marked done/cancelled',
        action_label='Review schedules',
        route=f'/admin/defense-scheduler?semester={semester_id}&status=scheduled',
    )
    _append_count_issue(
        issues,
        key='pending_grades',
        count=counts['pending_grades'],
        blocking=True,
        message='grade records are still pending or awaiting archive',
        action_label='Review grades',
        route=f'/admin/grade-center?semester={semester_id}&status=open',
    )

    _append_count_issue(
        issues,
        key='pit_peer_grading_windows',
        count=counts['pit_peer_grading_windows'],
        blocking=True,
        message='PIT peer grading windows are still enabled',
        action_label='Review PIT grading',
        route=f'/admin/grade-center?semester={semester_id}&scope=pit',
    )
    _append_count_issue(
        issues,
        key='incomplete_official_workflows',
        count=counts['incomplete_official_workflows'],
        blocking=True,
        message='official completion workflows are still incomplete',
        action_label='Review completion',
        route=f'/admin/grade-center?semester={semester_id}&official=incomplete',
    )
    return issues


def _append_count_issue(issues, *, key, count, blocking, message, action_label, route):
    if count <= 0:
        return
    issues.append({
        'key': key,
        'count': count,
        'blocking': blocking,
        'message': f'{count} {message}',
        'action_label': action_label,
        'route': route,
    })


def _semester_summary(semester):
    if semester is None:
        return None
    return {
        'id': semester.id,
        'label': semester.label,
        'school_year': semester.school_year.label,
        'school_year_id': semester.school_year_id,
        'display_name': semester.display_name,
        'starts_on': semester.starts_on.isoformat() if semester.starts_on else None,
        'ends_on': semester.ends_on.isoformat() if semester.ends_on else None,
    }
