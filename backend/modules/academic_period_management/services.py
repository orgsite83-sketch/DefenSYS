from django.db import transaction
from django.db.models import Q
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


def build_semester_transition_preview(target_semester):
    current_semester = (
        Semester.objects.select_related('school_year').filter(is_active=True).first()
    )
    target_semester = Semester.objects.select_related('school_year').get(
        pk=target_semester.pk,
    )

    if current_semester and current_semester.pk == target_semester.pk:
        return {
            'current_semester': _semester_summary(current_semester),
            'target_semester': _semester_summary(target_semester),
            'impact_counts': {},
            'issues': [],
            'blocking_reasons': [],
            'can_switch': True,
        }

    impact_counts = _impact_counts(current_semester)
    issues = _transition_issues(current_semester, impact_counts)
    blocking_reasons = [
        issue['message'] for issue in issues if issue.get('blocking')
    ]

    from student_teams.capstone_lifecycle import build_capstone_review
    review = build_capstone_review(current_semester, target_semester)
    if review['kind'] == 'exceptional' and review['total']:
        issues.append({'key': 'exceptional_transition', 'blocking': True,
            'message': 'This is not a consecutive regular-term transition. No automatic team continuation will be applied.',
            'action_label': 'Review teams', 'route': '/admin/student-teams'})
    if review['kind'] == 'close_cycle' and review['counts']['needs_review']:
        issues.append({'key': 'capstone_unresolved', 'blocking': True,
            'count': review['counts']['needs_review'],
            'message': 'Capstone teams still have unresolved grading, clearance, or cohort records.',
            'action_label': 'Review grades', 'route': '/admin/grade-center'})
    blocking_reasons = [issue['message'] for issue in issues if issue.get('blocking')]
    revision = sha256(json.dumps({'capstone': review['revision'], 'counts': impact_counts,
        'issues': issues}, sort_keys=True).encode()).hexdigest()
    return {
        'current_semester': _semester_summary(current_semester),
        'target_semester': _semester_summary(target_semester),
        'impact_counts': impact_counts,
        'issues': issues,
        'blocking_reasons': blocking_reasons,
        'can_switch': not blocking_reasons,
        'capstone_review': review,
        'preview_revision': revision,
    }


@transaction.atomic
def switch_active_semester(target_semester, user, force=False, reason='', *,
                           decisions=None, preview_revision='', request_id=None):
    reason = (reason or '').strip()
    if not (getattr(user, 'is_superuser', False) or getattr(user, 'role', None) == 'admin'):
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied('Only an administrator can activate a semester.')
    if request_id and (not isinstance(request_id, str) or len(request_id) > 64):
        raise ValidationError({'request_id': 'Use a request identity up to 64 characters.'})
    # All activation and enrollment paths lock periods in the same order.
    list(Semester.objects.select_for_update().order_by('pk'))
    if request_id:
        previous = SemesterTransitionLog.objects.filter(request_id=request_id).first()
        if previous:
            if previous.operation != 'activation' or previous.to_semester_id != target_semester.pk or previous.changed_by_id != user.pk:
                raise ValidationError('This request identity has already been used for another transition.')
            if previous.reason != reason or previous.forced != bool(force) or previous.impact_snapshot.get('decisions', []) != (decisions or []):
                raise ValidationError('This request has already completed with different decisions. Refresh the period before starting another review.')
            return previous.impact_snapshot, previous
    source = active_semester()
    if source and source.pk == target_semester.pk:
        if preview_revision or decisions:
            raise ValidationError({'code': 'stale_preview', 'detail': 'This semester is already active. Refresh the current roster.'})
        return build_semester_transition_preview(target_semester), None
    source_teams = StudentTeam.objects.filter(semester=source)
    from django.contrib.auth import get_user_model
    from student_teams.models import TeamMembership
    ids = set(source_teams.values_list('leader_id', flat=True)) | set(TeamMembership.objects.filter(team__in=source_teams).values_list('student_id', flat=True))
    list(get_user_model().objects.select_for_update().filter(pk__in=ids).order_by('pk'))
    from user_management.academic_records.models import StudentAcademicRecord
    list(StudentAcademicRecord.objects.select_for_update().filter(student_id__in=ids, semester=target_semester).order_by('pk'))
    list(source_teams.select_for_update().order_by('pk'))
    list(TeamGrade.all_objects.select_for_update().filter(team__in=source_teams).order_by('pk'))
    preview = build_semester_transition_preview(target_semester)

    review = preview.get('capstone_review', {})
    if review.get('requires_review') and preview_revision != preview.get('preview_revision'):
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
        applied = apply_capstone_transition(current, target, review, decisions or [],
            actor=user, log=log, reason=reason)
        log.impact_snapshot = {**preview, 'applied_team_ids': applied, 'decisions': decisions or []}
        log.save(update_fields=['impact_snapshot'])
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

    return log.impact_snapshot, log


def _impact_counts(current_semester):
    if current_semester is None:
        return {
            'active_teams': 0,
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

    return {
        'active_teams': StudentTeam.objects.filter(semester=current_semester).count(),
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


def _transition_issues(current_semester, counts):
    if current_semester is None:
        return []

    semester_id = current_semester.id
    issues = []

    _append_count_issue(
        issues,
        key='active_teams',
        count=counts['active_teams'],
        blocking=False,
        message='active teams are assigned to the current semester',
        action_label='Review teams',
        route=f'/admin/student-teams?semester={semester_id}',
    )
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

    has_active_work = counts['active_teams'] > 0
    if has_active_work and counts['capstone_peer_evaluation_enabled']:
        issues.append(_boolean_issue(
            key='capstone_peer_evaluation_enabled',
            message='peer evaluation is still enabled',
            action_label='Open evaluation settings',
            route='/admin/academic-periods',
        ))
    if has_active_work and counts['capstone_adviser_grading_enabled']:
        issues.append(_boolean_issue(
            key='capstone_adviser_grading_enabled',
            message='adviser grading is still enabled',
            action_label='Open evaluation settings',
            route='/admin/academic-periods',
        ))
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


def _boolean_issue(*, key, message, action_label, route):
    return {
        'key': key,
        'count': 1,
        'blocking': True,
        'message': message,
        'action_label': action_label,
        'route': route,
    }


def _semester_summary(semester):
    if semester is None:
        return None
    return {
        'id': semester.id,
        'label': semester.label,
        'school_year': semester.school_year.label,
        'school_year_id': semester.school_year_id,
        'display_name': semester.display_name,
    }
