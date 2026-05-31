from academic_period_management.models import Semester

from .models import FacultyRoleAssignment


ROLE_LABELS = {
    FacultyRoleAssignment.ROLE_PANELIST: 'Defense Panelist',
    FacultyRoleAssignment.ROLE_PIT_LEAD: 'PIT Lead',
    FacultyRoleAssignment.ROLE_ADVISER: 'Project Adviser',
    FacultyRoleAssignment.ROLE_REPO_ASSISTANT: 'Repository Assistant',
}

DISPLAY_ROLE_PRIORITY = [
  ('admin', 'Administrator', 'admin'),
  ('pit_lead', 'PIT Lead', 'pit_lead'),
  ('adviser', 'Adviser', 'adviser'),
  ('panelist', 'Panelist', 'panelist'),
  ('repo_assistant', 'Repository Assistant', 'repo_assistant'),
]


def _active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def snapshot_role_flags(user):
    return {
        FacultyRoleAssignment.ROLE_PANELIST: user.is_panelist,
        FacultyRoleAssignment.ROLE_PIT_LEAD: user.is_pit_lead,
        FacultyRoleAssignment.ROLE_ADVISER: user.is_adviser,
        FacultyRoleAssignment.ROLE_REPO_ASSISTANT: user.is_repo_assistant,
    }


def role_detail_for(user, role_key):
    if role_key == FacultyRoleAssignment.ROLE_PIT_LEAD:
        return user.pit_lead_year or None
    return None


def year_level_for(user, role_key):
    if role_key == FacultyRoleAssignment.ROLE_PIT_LEAD:
        return user.pit_lead_year or None
    if role_key == FacultyRoleAssignment.ROLE_REPO_ASSISTANT:
        return getattr(user, 'repo_assistant_year', None) or None
    return None


def record_role_changes(user, before_flags, changed_by=None):
    if user.role not in ('admin', 'faculty'):
        return

    after_flags = snapshot_role_flags(user)
    semester = _active_semester()

    for role_key, was_active in before_flags.items():
        is_active = after_flags.get(role_key, False)
        if was_active == is_active:
            continue

        FacultyRoleAssignment.objects.create(
            user=user,
            role_key=role_key,
            role_detail=role_detail_for(user, role_key) if is_active else None,
            semester=semester,
            year_level=year_level_for(user, role_key) if is_active else None,
            action=(
                FacultyRoleAssignment.ACTION_ASSIGNED
                if is_active
                else FacultyRoleAssignment.ACTION_REVOKED
            ),
            changed_by=changed_by,
        )


def _latest_role_assignment(user, role_key):
    return (
        FacultyRoleAssignment.objects.filter(user=user, role_key=role_key)
        .order_by('-changed_at', '-id')
        .first()
    )


def ensure_active_role_history(user, changed_by=None):
    """Backfill assigned rows for active roles missing history or last revoked."""
    if user.role not in ('admin', 'faculty'):
        return

    semester = _active_semester()
    after_flags = snapshot_role_flags(user)

    for role_key, is_active in after_flags.items():
        if not is_active:
            continue

        latest = _latest_role_assignment(user, role_key)
        if latest is not None and latest.action == FacultyRoleAssignment.ACTION_ASSIGNED:
            continue

        FacultyRoleAssignment.objects.create(
            user=user,
            role_key=role_key,
            role_detail=role_detail_for(user, role_key),
            semester=semester,
            year_level=year_level_for(user, role_key),
            action=FacultyRoleAssignment.ACTION_ASSIGNED,
            changed_by=changed_by,
        )


def compute_display_role(user):
    if user.role == 'admin':
        return {'key': 'admin', 'label': 'Administrator', 'tone': 'admin'}
    if user.role == 'student':
        semester = _active_semester()
        label = 'Student'
        record = None
        if semester:
            record = user.academic_records.filter(semester=semester).first()
        if not record:
            record = user.academic_records.order_by('-semester__school_year__label', '-semester__label').first()
        if record:
            label = record.year_level
        return {'key': 'student', 'label': label, 'tone': 'student'}

    if user.is_pit_lead:
        label = 'PIT Lead'
        if user.pit_lead_year:
            label = f'{label}: {user.pit_lead_year}'
        return {'key': 'pit_lead', 'label': label, 'tone': 'pit_lead'}
    if user.is_adviser:
        return {'key': 'adviser', 'label': 'Adviser', 'tone': 'adviser'}
    if user.is_panelist:
        return {'key': 'panelist', 'label': 'Panelist', 'tone': 'panelist'}
    if user.is_repo_assistant:
        return {
            'key': 'repo_assistant',
            'label': 'Repository Assistant',
            'tone': 'repo_assistant',
        }

    return {'key': 'faculty', 'label': 'Faculty Member', 'tone': 'faculty'}
