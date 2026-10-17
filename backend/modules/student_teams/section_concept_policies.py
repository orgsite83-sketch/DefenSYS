"""Review and apply section policies without changing a completed hearing."""
from copy import deepcopy

from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework.exceptions import ValidationError

from .concept_policy import (context_key, contexts_for, initial_concepts, resolve_policy,
                             team_policy_key, validate_override)


def policy_context_payload(team, teams, assignment):
    from repository.deliverables.concepts import latest_round
    from repository.deliverables.models import DeliverableSubmission
    result = []
    for stage in contexts_for(team):
        rows = []
        for member in teams:
            current = latest_round(member, stage)
            rows.append({'id': member.pk, 'name': member.name, 'project_title': member.project_title,
                'imported_assignment': member.concept_assignment,
                'override': (member.concept_policies or {}).get(team_policy_key(member, stage), {'mode': 'auto'}),
                'effective_policy': resolve_policy(member, stage, current=current, section_assignment=assignment),
                'locked': bool(current and current.schedule_id),
                'has_submissions': DeliverableSubmission.objects.filter(team=member,
                    project_version=member.project_version, stage_label=stage.label).exists()})
        result.append({'key': context_key(stage), 'label': stage.label,
            'policy': (assignment.concept_policies or {}).get(context_key(stage), {'mode': 'auto'}) if assignment else {'mode': 'auto'},
            'teams': rows})
    return result


def apply_policy_changes(team, teams, assignment, changes, *, confirmed=False):
    from repository.deliverables import concepts
    from repository.deliverables.models import ConceptRound, DeliverableSubmission
    from repository.deliverables.documents import sync_submission
    from repository.deliverables.services import get_deliverable_definitions_for_team
    from defense.scheduler.models import DefenseSchedule
    stages = {context_key(stage): stage for stage in contexts_for(team)}
    seen = set()
    for change in changes:
        key = change.get('context_key')
        if key not in stages or key in seen:
            raise ValidationError('Choose each enabled concept stage/event at most once within this section.')
        seen.add(key)
        stage = stages[key]
        old_policies = {member.pk: resolve_policy(member, stage, section_assignment=assignment) for member in teams}
        try:
            if 'section_policy' in change:
                policy = validate_override(change['section_policy'])
                assignment.concept_policies = {**assignment.concept_policies, key: policy}
            by_id = {member.pk: member for member in teams}
            seen_teams = set()
            for item in change.get('team_policies', []):
                member = by_id.get(item.get('team_id'))
                if member is None or member.pk in seen_teams:
                    raise ValidationError('Choose each team once and only from this section.')
                seen_teams.add(member.pk)
                policy = validate_override(item.get('policy'), team=True)
                member.concept_policies = {**member.concept_policies, team_policy_key(member, stage): policy}
        except (DjangoValidationError, TypeError, AttributeError) as exc:
            raise ValidationError(str(exc)) from exc
        for member in teams:
            new = resolve_policy(member, stage, use_round=False, section_assignment=assignment)
            old = old_policies[member.pk]
            changed = any(old.get(k) != new.get(k) for k in ('mode', 'required_count', 'assigned_title'))
            if new['mode'] == 'assigned' and not new['assigned_title']:
                raise ValidationError(f'Enter an assigned project/module title for {member.name} using a team exception.')
            if changed:
                current = concepts.latest_round(member, stage)
                schedules = DefenseSchedule.objects.filter(team=member, semester_id=member.semester_id,
                    project_version=member.project_version,
                    **({'event_name': stage.event_name, 'scope': 'pit'} if hasattr(stage, 'event_name') else
                       {'defense_stage': stage, 'scope': 'capstone'})).exclude(status='cancelled')
                # An unscheduled replacement round may be assigned a replacement by an admin.
                if (current and current.schedule_id) or (not current and schedules.exists()):
                    raise ValidationError(f'{member.name} already has a scheduled hearing. Its concept policy is locked.')
                submissions = DeliverableSubmission.objects.filter(team=member,
                    stage_label=stage.label, project_version=member.project_version)
                active_files = any(s.files.filter(is_current=True).exists() for s in submissions)
                if active_files and not confirmed:
                    raise ValidationError(f'Review the policy change for {member.name} and confirm it. Current papers will be kept in history and fresh concept papers required.')
                if current:
                    current.documents_snapshot = concepts.documents_snapshot(member, stage)
                    current.verdict = 'policy_changed'
                    current.remarks = 'Administrator changed the concept submission policy after reviewing affected work.'
                    current.save(update_fields=['documents_snapshot', 'verdict', 'remarks'])
                    # Preserve every previous round and file revision.
                    ConceptRound.objects.create(team=member, **concepts.context_fields(stage),
                        project_version=member.project_version, number=current.number + 1,
                        concepts=initial_concepts(new), policy_snapshot=deepcopy(new), review_required=True)
                definitions = {d['id']: d for d in get_deliverable_definitions_for_team(member, stage.label)}
                for submission in submissions:
                    definition = definitions.get(submission.deliverable_id)
                    if definition and (definition.get('file_policy') or {}).get('mode') == 'concepts':
                        submission.files.filter(is_current=True).update(is_current=False)
                        sync_submission(submission, definition, stage)
                if current or active_files:
                    concepts.invalidate_clearance(member, stage.label)
            member.save(update_fields=['concept_policies', 'updated_at'])
