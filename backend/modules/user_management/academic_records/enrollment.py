"""Shared read-only enrollment facts and ID-based import identity checks."""
from django.db.models import Count, F, Q

from .models import StudentAcademicRecord


def enrollment_names_agree(first, second):
    from defensys_backend.person_matching import DEFAULT_PERSON_NAMES, PersonNameIndex
    supplied = DEFAULT_PERSON_NAMES.account_parts(first.get('first_name', ''), first.get('last_name', ''))
    registered = DEFAULT_PERSON_NAMES.account_parts(second.get('first_name', ''), second.get('last_name', ''))
    # Older accounts may not yet have a complete name. IDs remain authoritative;
    # imports never replace the registered spelling or credentials.
    return not (all(supplied[:2]) and all(registered[:2]) and (
        supplied[1:] != registered[1:]
        or not PersonNameIndex.given_compatible(supplied[0], registered[0])
    ))


def existing_student_issue(user, row):
    if user.role != 'student':
        return f"ID '{user.username}' belongs to an existing {user.role} account."
    if not user.is_active:
        return f"Student '{user.username}' is inactive. Review the account before enrollment."
    if not enrollment_names_agree(row, {'first_name': user.first_name, 'last_name': user.last_name}):
        return f"Name does not match registered student '{user.username}'. Verify the student ID and official class list."
    return ''


def pending_enrollment_students(semester):
    """Confirmed live continuations, with their canonical destination year.

    Return a queryset and a student-to-target-year map for the same facts used
    by counts and the review list. No account/history-only enrollment inference.
    """
    from django.contrib.auth import get_user_model
    from student_teams.capstone_lifecycle import transition_kind
    from student_teams.models import StudentCapstonePlacement, TeamTermParticipation
    users = get_user_model().objects.filter(role='student', is_active=True)
    if semester is None:
        return users.none(), {}
    enrolled = StudentAcademicRecord.objects.filter(semester=semester)
    approved_teams = {}
    rows = TeamTermParticipation.objects.filter(
        semester=semester, closed_at__isnull=True, outcome='open',
        project_version=F('team__project_version'), team__semester=semester,
        team__participation_review_reason='', team__level__icontains='Capstone',
        transition__to_semester=semester,
        team__intake_semester_id=F('transition__from_semester_id'),
    ).select_related('transition__from_semester__school_year')
    for row in rows:
        impact = row.transition.impact_snapshot or {}
        if row.team_id not in impact.get('applied_team_ids', []):
            continue
        if any(team.get('team_id') == row.team_id and team.get('can_include') is True
               for team in impact.get('capstone_review', {}).get('teams', [])):
            approved_teams[row.team_id] = (
                StudentAcademicRecord.FOURTH_YEAR
                if transition_kind(row.transition.from_semester, semester) == 'continue' else None)
    pending = StudentCapstonePlacement.objects.filter(
        team_id__in=approved_teams, ended_at__isnull=True,
        participation__state='active', participation__student__is_active=True,
        participation__student__role='student',
        participation__intake_semester_id=F('team__intake_semester_id'),
    ).filter(
        Q(team__leader_id=F('participation__student_id'))
        | Q(team__memberships__student_id=F('participation__student_id'))
    ).exclude(participation__student_id__in=enrolled.values('student_id'))
    targets = {}
    for student_id, team_id in pending.values_list('participation__student_id', 'team_id').distinct():
        year = approved_teams[team_id]
        targets[student_id] = year if student_id not in targets or targets[student_id] == year else None
    return users.filter(pk__in=targets), targets


def enrollment_summary(semester):
    """Actual enrollment and confirmed pending groups; coverage is not a full intake."""
    if semester is None:
        return {'semester_id': None, 'enrolled': None, 'pending_continuations': None,
                'task_count': 0, 'reason': None, 'by_year': [], 'empty_years': [], 'pending_groups': [],
                'coverage': 'approved_continuations_only'}
    enrolled = StudentAcademicRecord.objects.filter(
        semester=semester, student__is_active=True, student__role='student')
    enrolled_by_year = dict(enrolled.values('year_level').annotate(
        total=Count('student_id', distinct=True)).values_list('year_level', 'total'))
    _, targets = pending_enrollment_students(semester)
    years = [year for year, _ in StudentAcademicRecord.YEAR_LEVEL_CHOICES]
    pending_by_year = {year: sum(target == year for target in targets.values()) for year in years}
    unclassified = sum(target not in years for target in targets.values())
    groups = [{'year_level': year, 'count': count} for year, count in pending_by_year.items() if count]
    if unclassified:
        groups.append({'year_level': None, 'count': unclassified})
    enrolled_count, pending_count = sum(enrolled_by_year.values()), len(targets)
    empty_years = [year for year in years if enrolled_by_year.get(year, 0) == 0]
    reason = ('no_enrollment' if enrolled_count == 0 else 'pending_continuations' if pending_count
              else 'empty_years' if empty_years else None)
    return {'semester_id': semester.pk, 'enrolled': enrolled_count,
            'pending_continuations': pending_count,
            # Keep one reminder for empty years without inventing expected-student
            # counts or duplicating confirmed pending-enrollment groups.
            'task_count': len(groups) or int(bool(empty_years)), 'reason': reason,
            'empty_years': empty_years,
            'coverage': 'approved_continuations_only', 'pending_groups': groups,
            'by_year': [{'year_level': year, 'enrolled': enrolled_by_year.get(year, 0),
                         'known_pending': pending_by_year[year]} for year in years]}
