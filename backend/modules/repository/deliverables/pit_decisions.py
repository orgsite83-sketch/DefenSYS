"""PIT Lead concept decisions; academic PIT results remain score-based."""
from hashlib import sha256
import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defensys_backend.read_projection import read_memoize
from . import concepts
from .models import ConceptRound


def can_manage(actor, team):
    if not actor or getattr(actor, 'is_guest_panelist', False):
        return False
    if getattr(actor, 'is_superuser', False) or getattr(actor, 'role', '') == 'admin':
        return True
    from student_teams.team_levels import normalize_year_level
    year = normalize_year_level(getattr(actor, 'pit_lead_year', '') or '')
    return bool(getattr(actor, 'role', '') == 'faculty' and getattr(actor, 'is_pit_lead', False)
                and year and year == normalize_year_level(team.year_level))


@read_memoize
def review_token(current):
    if not current:
        return ''
    state = {'id': current.pk, 'concepts': current.concepts, 'schedule': current.schedule_id,
             'outcome': current.verdict, 'cleared': str(current.revisions_cleared_at),
             'files': concepts.fingerprint(concepts.documents_snapshot(current.team, current.pit_event_config)),
             'system': current.section_round.selected_key if current.section_round_id else ''}
    return sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()


def unavailable_reason(team, stage, current):
    if not team.semester.is_active:
        return 'Historical concept rounds are read-only.'
    if stage.is_officially_complete:
        return 'This PIT event is officially complete.'
    if not current or not current.schedule_id:
        return 'Schedule the current concept set and complete the panel evaluations first.'
    if current.verdict:
        return 'The concept decision has already been recorded.'
    if (current.section_round_id and not current.section_round.selected_key
            and current.section_round.verdict != 'for_redefense'):
        return 'Select the shared section system before choosing the team module.'
    grade = current.schedule.grade_records.first()
    from defense.scheduler.panelist_evaluation import assessment_unavailable_reason
    return assessment_unavailable_reason(current.schedule, grade, action='recording the concept decision')


def completion_blocker(grade):
    if grade.scope != 'pit' or not concepts.enabled(grade.pit_event_config):
        return ''
    current = concepts.latest_round(grade.team, grade.pit_event_config)
    if not current or current.schedule_id != grade.schedule_id or not current.verdict:
        return 'The PIT Lead must record the concept selection before completing this event.'
    if current.verdict == 'for_redefense':
        return 'Complete the next concept review before completing this event.'
    if current.verdict == 'approved_with_revisions' and not current.revisions_cleared_at:
        return 'The PIT Lead must clear the concept revisions before completing this event.'
    from repository.section_concepts.services import module_pass_allowed
    if not module_pass_allowed(grade):
        return 'Clear the shared system revisions before completing this event.'
    return ''


@read_memoize(copy=True)
def decision_payload(team, stage, current, actor):
    manager = can_manage(actor, team)
    reason = unavailable_reason(team, stage, current) if manager else ''
    grade = (current.schedule.grade_records.first() if manager and current and current.schedule_id
             and current.verdict == 'approved_with_revisions' else None)
    return {'decision_scope': 'pit', 'can_manage_decision': manager,
            'can_record_decision': manager and not reason,
            'decision_unavailable_reason': reason,
            'decision_review_token': review_token(current) if manager else '',
            'decision': current.verdict if current else '',
            'decision_remarks': current.remarks if current else '',
            'selected_title': next((c['title'] for c in current.concepts
                if c.get('decision') in ('approved', 'approved_with_revisions')), '') if current else '',
            'can_clear_concept_revisions': bool(manager and current and current.verdict == 'approved_with_revisions'
                and not current.revisions_cleared_at and team.semester.is_active and not stage.is_officially_complete
                and grade and grade.status not in grade.LOCKED_STATUSES),
            'concept_revisions_cleared': bool(current and current.revisions_cleared_at),
            'decided_at': current.decided_at.isoformat() if current and current.decided_at else None,
            'decided_by_name': (current.decided_by.get_full_name() or current.decided_by.username)
                if current and current.decided_by else ''}


def audit(current, actor, action):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
        action=f'repository.pit_concept_{action}', target=current, actor=actor,
        reason=current.remarks, new_values={'team_id': current.team_id, 'round': current.number,
            'schedule_id': current.schedule_id, 'outcome': current.verdict, 'concepts': current.concepts}, strict=True)


@transaction.atomic
def record_decision(team, stage, actor, decisions, *, token, reason='', clear_revisions=False, module_review=False):
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    if not team.is_pit or not hasattr(stage, 'event_name'):
        raise ValidationError('This action applies to PIT events with concept selection enabled.')
    from defense.scheduler.models import PitEventGradingConfig
    # Share the team-first lock order used by paper uploads and endorsements.
    # Official completion checks the committed concept outcome before publishing.
    team = StudentTeam.objects.select_for_update().select_related('semester').get(pk=team.pk)
    stage = PitEventGradingConfig.objects.get(pk=stage.pk)
    concepts.require_context(team, stage)
    if not concepts.enabled(stage):
        raise ValidationError('This action applies to PIT events with concept selection enabled.')
    if not can_manage(actor, team):
        raise PermissionError('Only the assigned PIT Lead or an administrator can record PIT concept decisions.')
    current = concepts.latest_round(team, stage)
    if not current or not current.schedule_id:
        raise ValidationError('Schedule the current concept set before recording a decision.')
    if current.section_round_id and not module_review and not clear_revisions:
        raise ValidationError('Review this team\'s linked module in the shared section workspace. The section system is selected once for all teams.')
    if module_review and not current.section_round_id:
        raise ValidationError('Module reviews apply only to a shared section system.')
    if current.section_round_id and module_review and not clear_revisions and current.section_round.selected_key:
        selected_key = current.section_round.selected_key
        if not isinstance(decisions, list) or any(not isinstance(c, dict) or (
                c.get('key') != selected_key and c.get('decision') != 'not_selected') for c in decisions):
            raise ValidationError('Review only the module linked to the selected section system.')
    if not clear_revisions:
        blocker = unavailable_reason(team, stage, current)
        if blocker:
            raise ValidationError(blocker)
    schedule = DefenseSchedule.objects.select_for_update().get(pk=current.schedule_id)
    grade = TeamGrade.objects.select_for_update().filter(schedule=schedule).first()
    current = ConceptRound.objects.select_for_update().get(pk=current.pk)
    if not token or token != review_token(current):
        raise ValidationError('The concept set or papers changed. Refresh and review the current proposals.')
    if not team.semester.is_active or stage.is_officially_complete:
        raise ValidationError('Historical or officially completed PIT events are read-only.')
    if not grade or grade.project_version != team.project_version or grade.status in TeamGrade.LOCKED_STATUSES:
        raise ValidationError('This assessment is unavailable or finalized.')
    if not isinstance(reason, str) or len(reason) > 5000:
        raise ValidationError('Concept feedback must be text of up to 5000 characters.')
    if clear_revisions:
        if current.verdict != 'approved_with_revisions' or current.revisions_cleared_at:
            raise ValidationError('This concept decision has no outstanding revisions.')
        if not reason.strip():
            raise ValidationError('Record how the required concept revisions were resolved.')
        from .services import required_complete
        if not required_complete(team, stage.label):
            raise ValidationError('Accept every required concept document before clearing revisions.')
        selected = {c['key'] for c in current.concepts if c.get('decision') == 'approved_with_revisions'}
        def selected_files(snapshot):
            return sorted((f['id'], f['revision']) for submission in snapshot for f in submission['files']
                          if f.get('slot_key', '').split(':')[0] in selected)
        if selected_files(current.documents_snapshot) == selected_files(concepts.documents_snapshot(team, stage)):
            raise ValidationError('Upload and accept the revised selected-concept paper before clearing revisions.')
        current.revisions_cleared_at, current.revisions_cleared_by = timezone.now(), actor
        current.save(update_fields=['revisions_cleared_at', 'revisions_cleared_by'])
        log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.pit_concept_revisions_cleared', target=current, actor=actor,
            reason=reason.strip(), new_values={'team_id': team.pk, 'round': current.number}, strict=True)
        return
    blocker = unavailable_reason(team, stage, current)
    if blocker:
        raise ValidationError(blocker)
    if not isinstance(decisions, list) or any(not isinstance(c, dict) for c in decisions):
        raise ValidationError('Record a decision for every concept.')
    selected = [c for c in decisions if c.get('decision') in ('approved', 'approved_with_revisions')]
    if len(selected) > 1:
        raise ValidationError('Select exactly one concept.')
    outcome = selected[0]['decision'] if selected else 'for_redefense'
    if not selected and (not decisions or not all(c.get('decision') in ('rejected', 'revise', 'not_selected') for c in decisions)
                         or not any(c.get('decision') in ('rejected', 'revise') for c in decisions)):
        raise ValidationError('Select one concept or request revisions or replacement concepts.')
    if outcome != 'approved' and not reason.strip():
        raise ValidationError('Record the required changes or reason for another concept review.')
    concepts.record_outcome(grade, decisions, outcome=outcome, remarks=reason.strip(), actor=actor,
                            verification_required=any(c.get('decision') == 'revise' for c in decisions))
    grade.save(update_fields=['project_title_snapshot', 'updated_at'])
    if outcome == 'approved_with_revisions':
        # Reopen the chosen paper through the normal document revision path.
        # The presented files stay in the round snapshot and revision history.
        from .services import get_deliverable_definitions_for_team, review_submission
        from .models import DeliverableSubmission
        definition_ids = [d['id'] for d in get_deliverable_definitions_for_team(team, stage.label)
                          if (d.get('file_policy') or {}).get('mode') == 'concepts']
        selected_key = selected[0]['key']
        for submission in DeliverableSubmission.objects.filter(team=team, stage_label=stage.label,
                                                               deliverable_id__in=definition_ids):
            files = list(submission.files.filter(is_current=True, slot_key__startswith=f'{selected_key}:'))
            if not files:
                continue
            submission.revision_review_unlocked = True
            submission.save(update_fields=['revision_review_unlocked'])
            for file in files:
                review_submission(team, stage.label, submission.deliverable_id, 'rejected',
                                  selected[0].get('remarks', '').strip() or reason.strip(), actor, file_id=file.pk)
    if outcome == 'for_redefense':
        from defense.scheduler.services import transition_schedule_status
        transition_schedule_status(schedule, DefenseSchedule.STATUS_DONE, actor=actor,
                                   reason='PIT concept review recorded; another concept set is required.')
    current.refresh_from_db()
    audit(current, actor, 'decision')
