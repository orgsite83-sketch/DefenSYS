"""A minutes signature certifies a reviewed decision, rather than issuing it."""
import hashlib
import json

from django.core.exceptions import ValidationError

from grading.grades.deliberation import source_for, decision_payload
from grading.grades.outcome_rules import deliberation_policy


def for_minutes(minutes):
    if hasattr(minutes, '_preview_outcome'):
        return minutes._preview_outcome
    if minutes.outcome_snapshot:
        return minutes.outcome_snapshot
    if minutes.status != 'draft' or minutes.documenter_signed_at:
        return None
    return decision_payload(source_for(minutes.schedule), public=True)


def review_token(minutes):
    if not deliberation_policy(minutes.schedule):
        return ''
    data = [minutes.pk, minutes.status, str(minutes.updated_at), minutes.schedule.revision,
        for_minutes(minutes), [(row.pk, row.comments, str(row.updated_at))
        for row in minutes.current_panelist_comments]]
    return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()


def require_review(minutes, supplied, *, freeze=False):
    """Call inside the signature transaction; period/attempt writes share locks."""
    if not deliberation_policy(minutes.schedule):
        return
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    from .models import DefenseMinutes
    StudentTeam.objects.select_for_update().get(pk=minutes.schedule.team_id)
    DefenseSchedule.objects.select_for_update().get(pk=minutes.schedule_id)
    locked = DefenseMinutes.objects.select_for_update().select_related('schedule').get(pk=minutes.pk)
    official = decision_payload(source_for(locked.schedule), public=True)
    if not official:
        raise ValidationError('The assigned panel chair must confirm the outcome before signing minutes.')
    if not supplied or supplied != review_token(locked):
        raise ValidationError('The minutes or official outcome changed. Review the current PDF before signing.')
    if locked.outcome_snapshot and locked.outcome_snapshot != official:
        raise ValidationError('The signed decision changed. Start a reasoned minutes amendment before further signing.')
    if freeze:
        minutes.outcome_snapshot = official
