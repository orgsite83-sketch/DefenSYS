"""Chair-requested amendments use the existing administrator review queue."""
import uuid

from django.core.exceptions import ValidationError
from django.utils import timezone

from .deliberation import _entries, _text, decision_payload, source_for
from .outcome_rules import outcome_payload, policy_for


def amend(grade, data, *, actor):
    from .defense_workflow import is_chair, require_current, _record_outcome
    from .models import TeamGrade
    source = source_for(grade.schedule)
    if not source or not is_chair(grade, actor):
        raise ValidationError('An outcome amendment must be requested by the assigned panel chair.')
    require_current(grade)
    if not isinstance(data, dict) or set(data) - {'source_revision', 'review_token', 'verdict',
            'selected_key', 'reason', 'instructions', 'revision_entries', 'demo_requirements', 're_demo_required'}:
        raise ValidationError('Unsupported decision amendment fields.')
    rule = outcome_payload(grade)
    if data.get('source_revision') != source.revision or data.get('review_token') != rule['review_token']:
        raise ValidationError('The decision or assessment changed. Review a fresh amendment.')
    from defense.stages.models import StageGradingConfig
    if (grade.closed_as_failed or grade.schedule.status in ('cancelled', 'archived') or
            StageGradingConfig.objects.filter(semester=grade.semester, defense_stage=grade.defense_stage,
                                             is_officially_complete=True).exists()):
        raise ValidationError('Reopen the protected stage through its existing recovery process before amending its decision.')
    if TeamGrade.all_objects.filter(team=grade.team, project_version=grade.project_version,
            defense_stage__display_order__gt=grade.defense_stage.display_order).exists():
        raise ValidationError('A later stage has started. Reconcile downstream work before amending this decision.')
    if source.re_demos.filter(status='scheduled').exists():
        raise ValidationError('Cancel the active re-demo appointment before amending its source requirements.')
    verdict = data.get('verdict')
    if verdict not in rule['allowed_verdicts']:
        raise ValidationError('The corrected decision must follow the completed assessment and captured cutoff.')
    if (data.get('selected_key') or '') not in (source.selected_key, '' if verdict == 'for_redefense' else source.selected_key):
        raise ValidationError('This amendment preserves the official concept. Reconcile the selected concept separately before changing it.')
    reason = _text(data.get('reason', ''), 'Decision reason', 2000)
    instructions = _text(data.get('instructions', ''), 'Panel instructions')
    if verdict == 'for_redefense' and rule['outcome'] == 'approved' and (not reason or not instructions):
        raise ValidationError('Panel-directed re-defense needs its reason and required next action.')
    entries, requirements = _entries(policy_for(grade.schedule), data, verdict)
    # Keep identities for unchanged requirements, including verified items. New
    # identities are deterministic so the saved preview and application agree.
    prior = {(row['area_id'], row['text']): row['id'] for row in source.demo_requirements}
    for index, row in enumerate(requirements):
        row['id'] = prior.get((row['area_id'], row['text'])) or str(uuid.uuid5(
            source.request_id, f'{source.revision + 1}:{index}:{row["area_id"]}:{row["text"]}'))
    if (verdict == source.verdict and reason == source.reason and instructions == source.instructions
            and entries == source.revision_entries and requirements == source.demo_requirements):
        raise ValidationError('The amendment does not change the recorded decision.')
    if grade.revisions_cleared_at:
        raise ValidationError('Reopen revision clearance before changing its confirmed requirements.')
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).first()
    if verdict != source.verdict:
        if source.verdict == 'for_redefense' or source.re_demos.filter(status='done').exists():
            raise ValidationError('Repeat-attempt or verification evidence exists. Reconcile that evidence before changing the academic verdict.')
        if grade.status == 'published':
            raise ValidationError('Reopen the published grade before changing its academic verdict.')
        decisions = None
        if hearing:
            from .outcome_rules import concept_keys
            required = set(concept_keys(grade.schedule))
            decisions = [{'key': c['key'], 'decision': verdict if c['key'] == source.selected_key else
                'revise' if verdict == 'for_redefense' else 'not_selected', 'remarks': instructions,
                'next_action': 'revise' if verdict == 'for_redefense' else 'omit'} for c in hearing.concepts]
            if verdict == 'for_redefense':
                for row in decisions:
                    row['decision'] = 'revise' if row['key'] in required else 'not_selected'
                    row['next_action'] = 'revise' if row['key'] in required else 'omit'
        _record_outcome(grade, actor=actor, verdict=verdict, remarks=instructions or reason,
                        concept_decisions=decisions, panel_decision=True)
        grade.refresh_from_db()
    else:
        grade.verdict_remarks, grade.verdict_by, grade.verdict_at = instructions or reason, actor, timezone.now()
        grade.save(update_fields=['verdict_remarks', 'verdict_by', 'verdict_at', 'updated_at'])
        if hearing:
            hearing.remarks, hearing.decided_by, hearing.decided_at = instructions or reason, actor, grade.verdict_at
            hearing.concepts = [{**c, 'remarks': instructions if c.get('decision') in (
                'approved', 'approved_with_revisions', 'revise') else c.get('remarks', '')} for c in hearing.concepts]
            hearing.save(update_fields=['remarks', 'decided_by', 'decided_at', 'concepts'])
    source.history = [*source.history, {**decision_payload(source), 'assessment_snapshot': source.assessment_snapshot}]
    source.verdict, source.reason, source.instructions = verdict, reason, instructions
    source.selected_key = source.selected_key if verdict != 'for_redefense' else ''
    source.revision_entries, source.demo_requirements = entries, requirements
    source.confirmed_by, source.confirmed_at = actor, timezone.now()
    source.revision += 1
    source.save()
    TeamGrade.objects.filter(pk=grade.pk).update(outcome_metadata={**grade.outcome_metadata,
        'official_outcome_id': source.pk, 'official_outcome_revision': source.revision})
    from .automatic_outcomes import notify_assessment
    from django.db import transaction
    transaction.on_commit(lambda: notify_assessment(grade))
    return source
