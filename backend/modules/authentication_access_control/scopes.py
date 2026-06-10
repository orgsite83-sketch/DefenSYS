"""Shared row-level visibility scopes for authenticated users."""

from django.db.models import Q


def is_admin_user(user):
    return bool(
        user
        and getattr(user, 'is_authenticated', False)
        and (
            getattr(user, 'role', None) == 'admin'
            or getattr(user, 'is_superuser', False)
        )
    )


def is_pit_lead_only(user):
    return bool(
        user
        and getattr(user, 'is_authenticated', False)
        and getattr(user, 'is_pit_lead', False)
        and not is_admin_user(user)
    )


def _pit_year(user):
    return (getattr(user, 'pit_lead_year', None) or '').strip()


def pit_instructor_section_filters(user):
    from user_management.models import PitInstructorAssignment

    if not user or not getattr(user, 'is_authenticated', False):
        return Q(pk__in=[])

    assignments = PitInstructorAssignment.objects.filter(
        faculty=user,
        is_active=True,
    ).values_list('semester_id', 'year_level', 'section')

    query = Q(pk__in=[])
    for semester_id, year_level, section in assignments:
        if not section:
            continue
        query |= Q(
            semester_id=semester_id,
            level__icontains='PIT',
            year_level=year_level,
            section=section,
        )
    return query


def can_review_audit_logs(user):
    return is_admin_user(user) or (is_pit_lead_only(user) and bool(_pit_year(user)))


def visible_teams_for(user):
    from student_teams.models import StudentTeam

    base = (
        StudentTeam.objects.select_related('semester', 'semester__school_year', 'leader', 'adviser')
        .prefetch_related('memberships', 'memberships__student')
    )
    if not user or not getattr(user, 'is_authenticated', False):
        return base.none()
    if is_admin_user(user):
        return base
    if is_pit_lead_only(user):
        queryset = base.filter(level__icontains='PIT')
        pit_year = _pit_year(user)
        if pit_year:
            queryset = queryset.filter(year_level=pit_year)
        return queryset
    if getattr(user, 'is_uploader', False):
        return base
    if getattr(user, 'role', None) == 'faculty':
        return base.filter(Q(adviser=user) | pit_instructor_section_filters(user)).distinct()
    if getattr(user, 'role', None) == 'student':
        from student_teams.models import SectionAssignment
        pm_section = SectionAssignment.objects.filter(
            project_manager=user,
            semester__is_active=True
        ).first()
        if pm_section:
            return base.filter(
                Q(leader=user) | 
                Q(memberships__student=user) | 
                Q(section=pm_section.section, semester=pm_section.semester)
            ).distinct()
        return base.filter(Q(leader=user) | Q(memberships__student=user)).distinct()
    return base.none()


def manageable_teams_for(user):
    queryset = visible_teams_for(user)
    if is_admin_user(user) or is_pit_lead_only(user):
        return queryset
    return queryset.none()


def visible_schedules_for(user):
    from defense.scheduler.models import DefenseSchedule

    base = (
        DefenseSchedule.objects.select_related(
            'semester',
            'semester__school_year',
            'team',
            'team__leader',
            'team__adviser',
            'defense_stage',
            'rubric',
            'created_by',
        )
        .prefetch_related('panel_assignments', 'panel_assignments__panelist')
        .order_by('scheduled_date', 'start_time', 'team__name')
    )
    if not user or not getattr(user, 'is_authenticated', False):
        return base.none()
    if is_admin_user(user):
        return base
    if is_pit_lead_only(user):
        pit_year = _pit_year(user)
        if not pit_year:
            return base.none()
        return (
            base.filter(
                scope=DefenseSchedule.SCOPE_PIT,
                team__level__icontains='PIT',
                team__year_level=pit_year,
            )
            .exclude(team__year_level='3rd Year', semester__label='2nd Semester')
        )
    if getattr(user, 'is_uploader', False):
        return base
    if getattr(user, 'role', None) == 'faculty':
        return base.filter(
            Q(team__adviser=user)
            | Q(panel_assignments__panelist=user)
            | Q(team__in=visible_teams_for(user))
        ).distinct()
    if getattr(user, 'role', None) == 'student':
        from student_teams.models import SectionAssignment
        pm_section = SectionAssignment.objects.filter(
            project_manager=user,
            semester__is_active=True
        ).first()
        if pm_section:
            return base.filter(
                Q(team__leader=user) | 
                Q(team__memberships__student=user) |
                Q(team__section=pm_section.section, semester=pm_section.semester)
            ).distinct()
        return base.filter(
            Q(team__leader=user) | Q(team__memberships__student=user)
        ).distinct()
    return base.none()


def grade_records_for(user):
    from grading.grades.models import TeamGrade

    base = (
        TeamGrade.objects.select_related(
            'schedule',
            'schedule__rubric',
            'schedule__defense_stage',
            'defense_stage',
            'pit_event_config',
            'pit_event_config__panel_rubric',
            'pit_event_config__peer_rubric',
            'team',
            'team__leader',
            'team__adviser',
            'semester',
            'semester__school_year',
            'published_by',
        )
        .prefetch_related(
            'breakdowns',
            'breakdowns__rubric',
            'peer_member_grades',
            'peer_member_grades__student',
            'team__memberships',
            'team__memberships__student',
            'schedule__panel_assignments',
            'schedule__panel_assignments__panelist',
        )
    )
    if not user or not getattr(user, 'is_authenticated', False):
        return base.none()
    if is_admin_user(user):
        return base
    if is_pit_lead_only(user):
        pit_year = _pit_year(user)
        if not pit_year:
            return base.none()
        return (
            base.filter(
                scope=TeamGrade.SCOPE_PIT,
                team__level__icontains='PIT',
                team__year_level=pit_year,
            )
            .exclude(team__year_level='3rd Year', semester__label='2nd Semester')
        )
    if getattr(user, 'role', None) == 'faculty':
        return base.filter(
            Q(team__adviser=user)
            | Q(schedule__panel_assignments__panelist=user)
            | Q(team__in=visible_teams_for(user))
        ).distinct()
    if getattr(user, 'role', None) == 'student':
        return base.filter(
            Q(team__leader=user) | Q(team__memberships__student=user)
        ).distinct()
    return base.none()


def audit_logs_for(user):
    from .models import SystemAuditLog

    base = SystemAuditLog.objects.select_related('actor')
    if not user or not getattr(user, 'is_authenticated', False):
        return base.none()
    if is_admin_user(user):
        return base
    if is_pit_lead_only(user):
        pit_year = _pit_year(user)
        if not pit_year:
            return base.none()
        pit_marker = (
            Q(old_values__entry_type='pit')
            | Q(new_values__entry_type='pit')
            | Q(old_values__scope='pit')
            | Q(new_values__scope='pit')
            | Q(old_values__track='pit')
            | Q(new_values__track='pit')
        )
        year_marker = (
            Q(old_values__year_level=pit_year)
            | Q(new_values__year_level=pit_year)
            | Q(old_values__team_year_level=pit_year)
            | Q(new_values__team_year_level=pit_year)
            | Q(old_values__pit_year_level=pit_year)
            | Q(new_values__pit_year_level=pit_year)
        )
        return base.filter(pit_marker, year_marker)
    return base.none()
