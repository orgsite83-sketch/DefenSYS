from django.db import transaction
from django.db.models import Q
from rest_framework.exceptions import ValidationError

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam

from .models import Semester, SemesterTransitionLog


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

    return {
        'current_semester': _semester_summary(current_semester),
        'target_semester': _semester_summary(target_semester),
        'impact_counts': impact_counts,
        'issues': issues,
        'blocking_reasons': blocking_reasons,
        'can_switch': not blocking_reasons,
    }


def switch_active_semester(target_semester, user, force=False, reason=''):
    reason = (reason or '').strip()
    preview = build_semester_transition_preview(target_semester)

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
            from_semester=current,
            to_semester=target,
            changed_by=user if getattr(user, 'is_authenticated', False) else None,
            forced=bool(force),
            reason=reason,
            impact_snapshot=preview,
        )
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
        )

    return build_semester_transition_preview(target), log


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
