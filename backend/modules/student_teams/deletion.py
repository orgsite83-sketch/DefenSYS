"""Keep academic evidence; allow unused roster imports to be removed."""
from django.db.models import Q

from .models import HistoricalCapstoneJourney, StudentCapstoneParticipation, TeamStageProgress


def deletion_blockers(team):
    """Import-created placements and open term snapshots are setup, not evidence.

    Use unfiltered managers for versioned records so earlier project work cannot
    be erased by deleting the current roster. Force requests have the same rules.
    """
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    from repository.deliverables.models import DeliverableSubmission

    blockers = []
    if (team.term_participations.filter(
            Q(closed_at__isnull=False) | ~Q(outcome='open') | ~Q(semester_id=team.semester_id)).exists()
            or team.historical_recovery_records.exists()
            or HistoricalCapstoneJourney.objects.filter(team=team).exists()
            or team.student_placements.exclude(
                participation__state=StudentCapstoneParticipation.ACTIVE).exists()
            or team.project_version > 1 or team.participation_review_reason):
        blockers.append('This team has academic participation history that must be preserved.')
    if DefenseSchedule.objects.filter(team=team).exists():
        blockers.append('This team has defense schedules that must be preserved.')
    if TeamGrade.all_objects.filter(team=team).exists():
        blockers.append('This team has grade records or evaluations that must be preserved.')
    if DeliverableSubmission.all_objects.filter(team=team).exists() or team.documents.exists():
        blockers.append('This team has submitted documents that must be preserved.')
    if team.student_progress_reports.exists():
        blockers.append('This team has weekly progress reports that must be preserved.')
    if team.archive_entries.exists():
        blockers.append('This team has archived academic work that must be preserved.')
    if team.concept_rounds.exists() or team.section_project_links.exists():
        blockers.append('This team has concept workflow records that must be preserved.')
    if (TeamStageProgress.all_objects.filter(team=team).filter(
            ~Q(status=TeamStageProgress.STATUS_LOCKED) | Q(grade__isnull=False)
            | Q(ready_at__isnull=False) | Q(scheduled_at__isnull=False)
            | Q(graded_at__isnull=False) | Q(archived_at__isnull=False)).exists()
            or team.pit_endorsements.filter(endorsed_at__isnull=False).exists()
            or team.pit_event_rosters.filter(started_at__isnull=False).exists()):
        blockers.append('This team has recorded defense activity that must be preserved.')
    if team.people_assignments.exists():
        blockers.append('This team has saved defense assignments that must be preserved.')
    return blockers


def remove_unused_placements(team):
    """Run only after checking evidence, inside the deletion transaction.

    Release import-created placements before deleting their PROTECT-ed team.
    Remove only orphaned active intake identities, so a corrected re-import does
    not consume another participation number. Other teams and past intakes stay.
    """
    participation_ids = list(team.student_placements.values_list('participation_id', flat=True))
    team.student_placements.all().delete()
    StudentCapstoneParticipation.objects.filter(
        pk__in=participation_ids, state=StudentCapstoneParticipation.ACTIVE,
        placements__isnull=True, subsequent_participations__isnull=True,
    ).delete()
