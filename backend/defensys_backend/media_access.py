"""Authorize stored files through their owning application records."""

from django.contrib.auth import get_user_model
from django.db.models import Q

from authentication_access_control.scopes import is_admin_user, visible_teams_for


def _can_read_submission(user, submission):
    from defense.scheduler.models import DefenseSchedule
    from repository.deliverables.services import definition_for, team_queryset_for_user
    from repository.archive.services import capstone_visible_queryset, pit_visible_deliverables_queryset

    guest = getattr(user, 'is_guest_panelist', False)
    if not guest:
        # Team assignments grant access independently of the PIT cohort role.
        # Cohort access follows the same captured year as the archive listing.
        if team_queryset_for_user(user, include_pit_lead=False).filter(pk=submission.team_id).exists():
            return True
        if getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_pit_lead', False):
            from repository.project_archive.services import pit_deliverable_queryset_for_scope
            pit_year = (getattr(user, 'pit_lead_year', '') or '').strip()
            if pit_year and pit_deliverable_queryset_for_scope({
                'scope': 'pit_lead', 'pit_year_level': pit_year,
            }).filter(pk=submission.pk).exists():
                return True
        # The research repository intentionally shares accepted, unrestricted work.
        if (capstone_visible_queryset().filter(pk=submission.pk).exists()
                or pit_visible_deliverables_queryset().filter(pk=submission.pk).exists()):
            return True

    definition = definition_for(submission.team, submission.stage_label, submission.deliverable_id)
    if not definition or definition['type'] != 'pre' or not definition.get('is_defense_material'):
        return False
    schedules = DefenseSchedule.objects.filter(team_id=submission.team_id)
    if guest:
        from user_management.models import GuestPanelistCode
        from user_management.external_evaluators import invitation_is_available, invitation_schedule_ids

        invitation = GuestPanelistCode.objects.select_related('evaluator').filter(
            pk=user.guest_code_id, code=user.guest_code, is_active=True,
        ).first()
        if invitation is None or not invitation_is_available(invitation):
            return False
        schedules = schedules.filter(pk__in=invitation_schedule_ids(invitation), status=DefenseSchedule.STATUS_SCHEDULED)
    else:
        schedules = schedules.filter(Q(panel_assignments__panelist=user) | Q(documenter=user))
    return any(schedule.stage_label == submission.stage_label for schedule in schedules)


def can_read_media(user, name):
    """Unknown files fail closed; knowing a storage path grants no access."""
    from defense.minutes.models import DefenseMinutes
    from defense.minutes.views import has_minutes_view_permission
    from repository.archive.models import ArchiveEntry
    from repository.archive.services import pit_queryset
    from repository.deliverables.models import DeliverableSubmission
    from student_teams.documents.models import TeamDocument
    from student_teams.weekly_progress.models import WeeklyProgressReport

    guest = getattr(user, 'is_guest_panelist', False)
    admin = is_admin_user(user)
    from repository.section_concepts.models import SharedDeliverableFile
    from repository.section_concepts.shared_deliverables import can_read_file
    shared_file = (SharedDeliverableFile.objects.select_related('submission_set__section__semester',
        'submission_set__pit_event_config', 'submission_set__defense_stage').filter(file=name).first()
        if name.startswith('shared_deliverables/') else None)
    if shared_file:
        return can_read_file(user, shared_file)
    from repository.section_concepts.models import SectionConceptPaper
    from repository.section_concepts.shared_deliverables import can_read_legacy_file
    paper = SectionConceptPaper.objects.select_related('concept__round__project__section__semester').filter(file=name).first()
    if paper:
        return can_read_legacy_file(user, paper)
    submissions = DeliverableSubmission.objects.filter(
        Q(file=name) | Q(files__file=name),
    ).select_related('team', 'team__semester').distinct()
    for submission in submissions:
        if admin or _can_read_submission(user, submission):
            return True
    if guest:
        return False

    users = get_user_model().objects
    if users.filter(avatar=name).exists():
        return True
    if users.filter(e_signature=name).filter(Q(pk=user.pk) if not admin else Q()).exists():
        return True

    teams = visible_teams_for(user)
    from student_teams.documents.access import document_teams_for
    if TeamDocument.objects.filter(file=name, team__in=document_teams_for(user)).exists():
        return True
    from student_teams.weekly_progress.access import reports_for
    reports = reports_for(user).filter(report_file=name)
    if reports.exists():
        return True
    for minutes in DefenseMinutes.objects.filter(pdf_file=name).select_related('schedule__team'):
        if has_minutes_view_permission(user, minutes.schedule):
            return True
    entries = ArchiveEntry.objects.filter(file=name)
    if admin and entries.exists():
        return True
    if entries.filter(team__in=teams).exists():
        return True
    return pit_queryset().filter(file=name).exists()
