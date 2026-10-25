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
        from repository.section_concepts.services import project_for
        project = project_for(team, stage)
        rows = []
        for member in teams:
            current = latest_round(member, stage)
            rows.append({'id': member.pk, 'name': member.name, 'project_title': member.project_title,
                'imported_assignment': member.concept_assignment,
                'override': (member.concept_policies or {}).get(team_policy_key(member, stage), {'mode': 'auto'}),
                'effective_policy': resolve_policy(member, stage, current=current, section_assignment=assignment),
                'locked': bool(current and (current.schedule_id or current.verdict or current.number > 1)),
                'needs_requirement_update': bool(current and (len(current.concepts) != stage.concept_config.get('required_count', 3)
                    or (current.policy_snapshot or {}).get('mode') == 'assigned')),
                'has_submissions': DeliverableSubmission.objects.filter(team=member,
                    project_version=member.project_version, stage_label=stage.label).exists()})
        result.append({'key': context_key(stage), 'label': stage.label,
            'required_count': stage.concept_config.get('required_count', 3),
            'section_project_id': project.pk if project else None,
            'policy': (assignment.concept_policies or {}).get(context_key(stage), {'mode': 'auto'}) if assignment else {'mode': 'auto'},
            'teams': rows})
    return result


def apply_policy_changes(team, teams, assignment, changes, *, confirmed=False, actor=None):
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
        from repository.section_concepts.services import project_for
        if project_for(team, stage):
            raise ValidationError('Manage shared system and corresponding module proposals in the section concept workspace.')
        reconcile_ids = change.get('reconcile_team_ids', [])
        if reconcile_ids:
            by_id = {member.pk: member for member in teams}
            if not isinstance(reconcile_ids, list) or any(type(pk) is not int or pk not in by_id for pk in reconcile_ids) or len(set(reconcile_ids)) != len(reconcile_ids):
                raise ValidationError('Choose each team once and only from this section.')
            if not confirmed:
                raise ValidationError('Review and confirm the configured concept count before applying it.')
            if type(change.get('expected_required_count')) is not int:
                raise ValidationError('Refresh and review the configured count before applying it.')
            for pk in reconcile_ids:
                concepts.reconcile_initial_requirements(by_id[pk], stage, actor,
                    expected_count=change['expected_required_count'])
        if 'section_policy' not in change and not change.get('team_policies'):
            continue
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
            current = concepts.latest_round(member, stage)
            if current and (current.policy_snapshot or {}).get('redefense_plan'):
                if member.pk in seen_teams:
                    # A legacy assigned replacement is controlled by the
                    # captured panel plan, independently of the initial count.
                    explicit = (member.concept_policies or {}).get(team_policy_key(member, stage), {})
                    new = {**old, **explicit}
                    if explicit.get('mode') == 'assigned':
                        new['required_count'] = 1
                    if (current.schedule_id or new.get('mode') != old.get('mode') or
                            new.get('required_count') != old.get('required_count')):
                        raise ValidationError('The panel-requested concept set is fixed for this hearing.')
                    if new.get('assigned_title') != old.get('assigned_title'):
                        if old.get('mode') != 'assigned' or not new.get('assigned_title'):
                            raise ValidationError('Assign the requested replacement project/module title.')
                        if len(current.concepts) != 1 or current.concepts[0].get('requested_action') != 'replace':
                            raise ValidationError('Only the requested assigned replacement title can be changed here.')
                        concept_ids = [d['id'] for d in get_deliverable_definitions_for_team(member, stage.label)
                                       if (d.get('file_policy') or {}).get('mode') == 'concepts']
                        has_current_papers = DeliverableSubmission.objects.filter(team=member,
                            stage_label=stage.label, deliverable_id__in=concept_ids, files__is_current=True).exists()
                        if has_current_papers and not confirmed:
                            raise ValidationError(f'Review the assignment change for {member.name} and confirm it. Current papers will be kept in history and fresh concept papers required.')
                        current.concepts = [{**current.concepts[0], 'title': new['assigned_title']}]
                        current.policy_snapshot = {**current.policy_snapshot, 'assigned_title': new['assigned_title']}
                        current.save(update_fields=['concepts', 'policy_snapshot'])
                        if has_current_papers:
                            from repository.deliverables.redefense import refresh_files
                            refresh_files(member, stage)
                        concepts.invalidate_clearance(member, stage.label)
                # Section defaults apply to future initial hearings; a live chair
                # request must not grow back to the initial count during edits.
                member.save(update_fields=['concept_policies', 'updated_at'])
                continue
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
