from django.contrib.auth import get_user_model
from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction

from user_management.models import FacultyRoleAssignment
from user_management.role_assignments import record_role_changes, snapshot_role_flags

User = get_user_model()

PIT_YEAR_CHOICES = ('1st Year', '2nd Year', '3rd Year', '4th Year')


def _display_name(user):
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


def require_pit_lead(user):
    if getattr(user, 'role', None) not in ('faculty', 'admin') or not getattr(user, 'is_pit_lead', False):
        raise PermissionDenied('Only PIT leads can manage repository assistant assignments.')
    pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
    if not pit_year:
        raise ValidationError('PIT lead year level is not configured.')
    return pit_year


def current_repo_assistant_for_year(year_level):
    return (
        User.objects.filter(
            role__in=['faculty', 'admin'],
            is_active=True,
            is_repo_assistant=True,
            repo_assistant_year=year_level,
        )
        .order_by('last_name', 'first_name', 'username')
        .first()
    )


def has_repo_assistant_for_year(year_level):
    if not year_level:
        return False
    return current_repo_assistant_for_year(year_level) is not None


def faculty_assignment_candidates(pit_lead, pit_year):
    return (
        User.objects.filter(role__in=['faculty', 'admin'], is_active=True)
        .exclude(pk=pit_lead.pk)
        .order_by('last_name', 'first_name', 'username')
    )


def _revoke_repo_assistant(user, *, changed_by=None, year_level=''):
    if not user.is_repo_assistant and not (user.repo_assistant_year or '').strip():
        return
    before = snapshot_role_flags(user)
    user.is_repo_assistant = False
    user.is_uploader = False
    user.repo_assistant_year = ''
    user.save(update_fields=['is_repo_assistant', 'is_uploader', 'repo_assistant_year'])
    record_role_changes(user, before, changed_by=changed_by)


def repository_assistant_assignment_payload(pit_lead):
    pit_year = require_pit_lead(pit_lead)
    assigned = current_repo_assistant_for_year(pit_year)
    candidates = [
        {
            'id': faculty.id,
            'name': _display_name(faculty),
            'email': faculty.email,
            'username': faculty.username,
        }
        for faculty in faculty_assignment_candidates(pit_lead, pit_year)
    ]
    return {
        'year_level': pit_year,
        'assigned': (
            {
                'id': assigned.id,
                'name': _display_name(assigned),
                'email': assigned.email,
                'username': assigned.username,
            }
            if assigned
            else None
        ),
        'candidates': candidates,
    }


@transaction.atomic
def assign_repository_assistant(pit_lead, faculty_id):
    pit_year = require_pit_lead(pit_lead)
    if not faculty_id:
        raise ValidationError({'faculty_id': 'Select a faculty member to assign.'})

    try:
        faculty_id = int(faculty_id)
    except (TypeError, ValueError) as exc:
        raise ValidationError({'faculty_id': 'Invalid faculty id.'}) from exc

    target = User.objects.filter(pk=faculty_id, role__in=['faculty', 'admin'], is_active=True).first()
    if target is None:
        raise ValidationError({'faculty_id': 'Faculty member not found.'})
    if target.pk == pit_lead.pk:
        raise ValidationError({'faculty_id': 'You cannot assign yourself as repository assistant.'})
    if getattr(target, 'is_pit_lead', False):
        raise ValidationError({'faculty_id': 'PIT leads cannot be assigned as repository assistant.'})

    existing = current_repo_assistant_for_year(pit_year)
    if existing and existing.pk != target.pk:
        _revoke_repo_assistant(existing, changed_by=pit_lead, year_level=pit_year)

    before = snapshot_role_flags(target)
    target.is_repo_assistant = True
    target.is_uploader = True
    target.repo_assistant_year = pit_year
    target.save(update_fields=['is_repo_assistant', 'is_uploader', 'repo_assistant_year'])
    record_role_changes(target, before, changed_by=pit_lead)

    return repository_assistant_assignment_payload(pit_lead)
