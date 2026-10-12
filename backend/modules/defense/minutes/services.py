"""Build minutes from both institutional and external panel assignments."""
from django.db import transaction
from django.db.models import Q

from user_management.models import GuestPanelistCode
from .models import DefenseMinutes, MinutesPanelistComment


def minutes_panel_roster(schedule):
    """Guest access expiry/revocation does not erase a defense assignment."""
    assignments = sorted(schedule.panel_assignments.select_related('panelist').all(),
                         key=lambda item: (not item.is_chair, item.order, item.panelist.username))
    roster = []
    member_count = 1
    for assignment in assignments:
        role = 'Chair' if assignment.is_chair else f'Panel Member {member_count}'
        if not assignment.is_chair:
            member_count += 1
        roster.append({
            'panelist_id': assignment.panelist_id, 'guest_invitation_id': None,
            'name': assignment.panelist.get_full_name() or assignment.panelist.username,
            'role': role, 'is_chair': assignment.is_chair, 'is_external': False,
        })

    # Include older, single-defense codes as well as session invitations.
    invitations = GuestPanelistCode.objects.filter(
        Q(schedules=schedule) | Q(defense_schedule=schedule)
    ).distinct().order_by('guest_name', 'pk')
    seen = set()
    for invitation in invitations:
        identity = ('evaluator', invitation.evaluator_id) if invitation.evaluator_id else ('guest', invitation.pk)
        if identity in seen:
            continue
        seen.add(identity)
        roster.append({
            'panelist_id': None, 'guest_invitation_id': invitation.pk,
            'name': invitation.guest_name, 'role': 'External Panelist',
            'is_chair': False, 'is_external': True,
        })
    return roster


def missing_panelist_comments(minutes, comments):
    """Return unsaved sections, also usable by the read-only draft preview."""
    faculty_ids = {comment.panelist_id for comment in comments if comment.panelist_id is not None}
    guest_ids = {comment.guest_invitation_id for comment in comments if comment.guest_invitation_id is not None}
    missing = []
    for order, member in enumerate(minutes_panel_roster(minutes.schedule)):
        if ((member['panelist_id'] is not None and member['panelist_id'] in faculty_ids)
                or (member['guest_invitation_id'] is not None and member['guest_invitation_id'] in guest_ids)):
            continue
        missing.append(MinutesPanelistComment(
            minutes=minutes, panelist_id=member['panelist_id'], guest_invitation_id=member['guest_invitation_id'],
            panelist_name_snapshot=member['name'], panelist_role_snapshot=member['role'], display_order=order,
        ))
    return missing


@transaction.atomic
def sync_panelist_comments(minutes):
    """Add missing draft sections without overwriting comments or signed records."""
    locked = DefenseMinutes.objects.select_for_update().get(pk=minutes.pk)
    if locked.status != DefenseMinutes.STATUS_DRAFT or locked.pdf_file or locked.documenter_signed_at:
        return
    missing = missing_panelist_comments(minutes, list(locked.panelist_comments.all()))
    if missing:
        MinutesPanelistComment.objects.bulk_create(missing)
        getattr(minutes, '_prefetched_objects_cache', {}).pop('panelist_comments', None)
