"""Concept selection, version-specific clearance and hearing history."""
from copy import deepcopy
from hashlib import sha256
import json
from defensys_backend.read_projection import read_memoize
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from .models import ConceptRound, DeliverableSubmission
from .documents import current_files, file_payload, completeness
from student_teams.concept_policy import resolve_policy, initial_concepts


@read_memoize
def stage_for(team, label):
    from defense.stages.models import DefenseStage
    if team.is_capstone:
        return DefenseStage.objects.filter(label=label).first()
    from defense.scheduler.event_scope import pit_events_for_team
    return pit_events_for_team(team).filter(event_name__iexact=label).first()


def context_for_grade(grade):
    return grade.defense_stage if grade.scope == 'capstone' else grade.pit_event_config


def context_fields(stage):
    return {'pit_event_config': stage} if hasattr(stage, 'event_name') else {'defense_stage': stage}


def require_context(team, stage):
    if hasattr(stage, 'event_name'):
        from defense.scheduler.event_scope import pit_year
        if (not team.is_pit or not pit_year(team.year_level) or stage.year_level != team.year_level
                or stage.semester_id != team.semester_id):
            raise ValidationError('Concepts must belong to this team’s PIT year level and semester.')
    elif not team.is_capstone:
        raise ValidationError('PIT teams must use their own year-scoped event concepts.')


def reviewer_name(stage):
    return 'assigned instructor or PIT Lead' if hasattr(stage, 'event_name') else 'adviser'


def enabled(stage):
    return bool(stage and (stage.concept_config or {}).get('enabled'))


@read_memoize
def latest_round(team, stage):
    if not enabled(stage):
        return None
    require_context(team, stage)
    return ConceptRound.objects.filter(team=team, **context_fields(stage),
        project_version=team.project_version).order_by('-number', '-pk').first()


@transaction.atomic
def get_round(team, stage):
    from student_teams.models import StudentTeam
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    if hasattr(stage, 'event_name'):
        from defense.scheduler.models import PitEventGradingConfig
        locked = PitEventGradingConfig.objects.select_for_update().get(pk=stage.pk)
        stage.concept_config = locked.concept_config
        require_context(team, locked)
    if not enabled(stage):
        raise ValidationError('Concept selection is not enabled for this stage or PIT event.')
    current = latest_round(team, stage)
    if current:
        return current
    policy = resolve_policy(team, stage, use_round=False)
    return ConceptRound.objects.create(team=team, **context_fields(stage), project_version=team.project_version,
        section_round_id=policy.get('section_round_id'), policy_snapshot=policy, concepts=initial_concepts(policy))


def documents_snapshot(team, stage, *, clearance_only=False):
    from .services import get_deliverable_definitions_for_team
    from .documents import slots_for
    definitions = {d['id']: d for d in get_deliverable_definitions_for_team(team, stage.label)}
    submissions = DeliverableSubmission.objects.filter(team=team, stage_label=stage.label).prefetch_related('files')
    if clearance_only:
        from .services import get_deliverable_definitions_for_team
        ids = [d['id'] for d in get_deliverable_definitions_for_team(team, stage.label)
               if d['type'] == 'pre' and d.get('requirement_timing') != 'defense']
        submissions = submissions.filter(deliverable_id__in=ids)
    return [{'deliverable_id': s.deliverable_id, 'label': s.label,
             'is_defense_material': definitions.get(s.deliverable_id, {}).get('is_defense_material', False),
             'document_labels': {slot['key']: slot['label'] for slot in slots_for(definitions.get(s.deliverable_id, {'label': s.label}), stage=stage)},
             'files': [file_payload(f) for f in current_files(s)]}
            for s in submissions]


def fingerprint(snapshot):
    return sorted((s['deliverable_id'], f['id'], f['revision']) for s in snapshot for f in s['files'])


def titles_complete(current):
    return bool(current and current.concepts and all(c.get('title', '').strip() for c in current.concepts))


def module_review_token(team, stage):
    current = latest_round(team, stage)
    policy = resolve_policy(team, stage, current=current)
    state = {'round': current.pk if current else None,
             'concepts': current.concepts if current else initial_concepts(policy)}
    if current and current.section_round_id:
        state['systems'] = list(current.section_round.systems.order_by('key').values('id', 'title'))
    return sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()


def clearance_valid(team, stage, current=None):
    current = current or latest_round(team, stage)
    if current and not current.schedule_id and not current.review_required:
        return False
    return bool(current and current.endorsed_at and
        fingerprint(current.endorsement_snapshot) == fingerprint(documents_snapshot(team, stage, clearance_only=True)))


def clearance_blocker(team, stage):
    if not enabled(stage):
        return ''
    current = latest_round(team, stage)
    if not titles_complete(current):
        return 'Submit a title and the required documents for every concept.'
    from repository.section_concepts.services import scheduling_blocker
    shared_blocker = scheduling_blocker(team, stage, current)
    if shared_blocker:
        return shared_blocker
    if (not current.schedule_id or current.review_required) and not clearance_valid(team, stage, current):
        return f'The current concept set needs {reviewer_name(stage)} review and endorsement before scheduling.'
    from .services import get_deliverable_definitions_for_team, submissions_for
    submitted = submissions_for(team, stage.label)
    for d in get_deliverable_definitions_for_team(team, stage.label):
        if d.get('source') == 'defense_minutes' or not d['required'] or d['type'] != 'pre' or d.get('requirement_timing') == 'defense':
            continue
        if not completeness(submitted.get(d['id']), d, accepted=True, stage=stage):
            return 'Complete the required concept documents before scheduling.'
    return ''


def pit_ready(team, config):
    """Concept hearings can repeat only after the current round is cleared."""
    if not enabled(config):
        return True
    require_context(team, config)
    current = latest_round(team, config)
    if current and current.schedule_id and current.schedule.status != 'cancelled':
        return False
    return not clearance_blocker(team, config)


def invalidate_clearance(team, stage_label, deliverable_id=None):
    if deliverable_id:
        from .services import definition_for
        definition = definition_for(team, stage_label, deliverable_id)
        if not definition or definition['type'] != 'pre' or definition.get('requirement_timing') == 'defense':
            return
    stage = stage_for(team, stage_label)
    current = latest_round(team, stage)
    if current and current.schedule_id is None:
        current.endorsed_at = None
        current.endorsed_by = None
        current.override_reason = ''
        current.endorsement_snapshot = []
        current.save(update_fields=['endorsed_at', 'endorsed_by', 'override_reason', 'endorsement_snapshot'])
        if team.ready_for_stage == stage_label:
            team.ready_for_stage = None
            team.save(update_fields=['ready_for_stage', 'updated_at'])


def endorse(team, stage, actor):
    if not enabled(stage):
        return
    current = get_round(team, stage)
    if not titles_complete(current):
        raise ValueError('Enter a title for every concept before endorsement.')
    if current.schedule_id:
        raise ValueError('This concept set is already attached to a defense.')
    if current.section_round_id and not all(c.get('faculty_confirmed') for c in current.concepts):
        raise ValueError('Faculty must confirm all three module names and their system connections before endorsement.')
    from repository.section_concepts.services import module_blocker
    shared_blocker = module_blocker(team, stage, current)
    if shared_blocker:
        raise ValueError(shared_blocker)
    current.endorsed_at, current.endorsed_by = timezone.now(), actor
    current.review_required = True
    current.endorsement_snapshot = documents_snapshot(team, stage, clearance_only=True)
    current.save(update_fields=['endorsed_at', 'endorsed_by', 'endorsement_snapshot', 'review_required'])
    from grading.grades.models import TeamGrade
    if actor:
        TeamGrade.objects.filter(team=team, **context_fields(stage), semester=team.semester,
            verdict='for_redefense', redefense_verification_required=True).update(
                redefense_verified_at=current.endorsed_at, redefense_verified_by=actor,
                clearance_remarks='Reviewed the current concept papers and endorsed this concept set.')


def bind_schedule(schedule):
    stage = stage_for(schedule.team, schedule.stage_label)
    if not enabled(stage):
        return
    if ConceptRound.objects.filter(schedule=schedule).exists():
        return
    current = get_round(schedule.team, stage)
    if current.schedule_id and current.schedule_id != schedule.pk:
        from defense.scheduler.models import DefenseSchedule
        if current.schedule.status != DefenseSchedule.STATUS_CANCELLED:
            raise ValidationError('This concept set already belongs to another hearing.')
    if not current.schedule_id or current.schedule_id != schedule.pk:
        blocker = clearance_blocker(schedule.team, stage)
        if blocker:
            raise ValidationError(blocker)
        current.schedule = schedule
        current.documents_snapshot = documents_snapshot(schedule.team, stage)
        current.save(update_fields=['schedule', 'documents_snapshot'])


def validate_decisions(current, decisions, verdict, replacement_required):
    if not isinstance(decisions, list) or len(decisions) != len(current.concepts):
        raise ValidationError('Record a decision for every concept in this hearing.')
    if any(not isinstance(d, dict) or not isinstance(d.get('key'), str) for d in decisions):
        raise ValidationError('Each concept needs one valid decision key.')
    keyed = {d.get('key'): d for d in decisions if isinstance(d, dict)}
    if len(keyed) != len(current.concepts):
        raise ValidationError('Each concept needs one unique decision.')
    selected = []
    concepts = deepcopy(current.concepts)
    for c in concepts:
        d = keyed.get(c['key'], {})
        if d.get('decision') not in ('approved', 'approved_with_revisions', 'rejected', 'not_selected', 'revise'):
            raise ValidationError('Choose an outcome for every concept.')
        remarks = d.get('remarks', '')
        if not isinstance(remarks, str) or len(remarks) > 5000:
            raise ValidationError('Concept feedback must be text of up to 5000 characters.')
        if d['decision'] in ('rejected', 'revise', 'approved_with_revisions') and not remarks.strip():
            raise ValidationError('Explain concept rejection or required revisions.')
        c.update(decision=d['decision'], remarks=remarks.strip())
        if d['decision'] in ('approved', 'approved_with_revisions'):
            selected.append(c)
    if verdict in ('approved', 'approved_with_revisions'):
        if len(selected) != 1 or selected[0]['decision'] != verdict:
            raise ValidationError('Select exactly one concept matching the hearing approval verdict.')
    elif selected:
        raise ValidationError('An approved concept requires an approval verdict for this hearing.')
    if all(c['decision'] == 'rejected' for c in concepts) and verdict == 'for_redefense':
        replacement_required = True
    if replacement_required and verdict != 'for_redefense':
        raise ValidationError('Replacement concepts for another hearing require a For re-defense verdict.')
    return concepts, replacement_required, selected


def record_outcome(grade, decisions, *, replacement_required=False, outcome=None, remarks=None, actor=None,
                   verification_required=None):
    # PIT records a concept decision on the round, independently of academic grades.
    outcome = outcome if outcome is not None else grade.verdict
    remarks = remarks if remarks is not None else grade.verdict_remarks
    actor = actor or grade.verdict_by
    verification_required = (grade.redefense_verification_required if verification_required is None
                             else verification_required)
    stage = context_for_grade(grade)
    if not enabled(stage):
        return
    require_context(grade.team, stage)
    current = ConceptRound.objects.filter(schedule_id=grade.schedule_id).first() if grade.schedule_id else None
    if not current:
        raise ValidationError('This defense needs a scheduled concept set before a verdict can be recorded.')
    if latest_round(grade.team, stage).pk != current.pk:
        raise ValidationError('An earlier concept hearing is read-only after the next round has started.')
    concepts, replacement_required, selected = validate_decisions(current, decisions, outcome, replacement_required)
    from repository.section_concepts.services import validate_module_decision
    validate_module_decision(grade, current, concepts, outcome=outcome)
    current.concepts, current.verdict, current.remarks = concepts, outcome, remarks
    current.decided_by, current.decided_at = actor, timezone.now()
    current.replacement_required = replacement_required
    current.documents_snapshot = documents_snapshot(grade.team, stage)
    current.save(update_fields=['concepts', 'verdict', 'remarks', 'replacement_required', 'documents_snapshot',
                               'decided_by', 'decided_at'])
    if selected:
        grade.team.project_title = selected[0]['title']
        grade.team.project_pending = False
        grade.team.save(update_fields=['project_title', 'project_pending', 'updated_at'])
        grade.project_title_snapshot = selected[0]['title']
    if outcome != 'for_redefense':
        return
    snapshot = resolve_policy(grade.team, stage, current=current)
    review = True
    replacement_key = current.section_round.selected_key if current.section_round_id else ''
    next_concepts = [{**c, 'title': '' if replacement_required and (not replacement_key or c['key'] == replacement_key) else c['title'],
        **({'faculty_confirmed': False} if current.section_round_id and replacement_required and (
            not replacement_key or c['key'] == replacement_key) else {}), 'decision': '', 'remarks': ''} for c in concepts]
    next_round = ConceptRound.objects.create(team=grade.team, **context_fields(stage),
        project_version=grade.project_version, number=current.number + 1,
        section_round_id=current.section_round_id, concepts=next_concepts, review_required=review,
        policy_snapshot={**snapshot, **({'assigned_title': ''} if replacement_required else {})})
    if replacement_required:
        from .services import get_deliverable_definitions_for_team
        from .documents import sync_submission
        concept_ids = [d['id'] for d in get_deliverable_definitions_for_team(grade.team, stage.label)
                       if (d.get('file_policy') or {}).get('mode') == 'concepts']
        for submission in DeliverableSubmission.objects.filter(team=grade.team, stage_label=stage.label, deliverable_id__in=concept_ids):
            files = submission.files.filter(is_current=True)
            if replacement_key:
                files = files.filter(slot_key__startswith=f'{replacement_key}:')
            files.update(is_current=False)
            definition = next(d for d in get_deliverable_definitions_for_team(grade.team, stage.label) if d['id'] == submission.deliverable_id)
            sync_submission(submission, definition, stage)
    if grade.team.ready_for_stage == stage.label:
        grade.team.ready_for_stage = None
        grade.team.save(update_fields=['ready_for_stage', 'updated_at'])


@transaction.atomic
def save_titles(team, stage, concepts, *, actor=None):
    from student_teams.models import StudentTeam
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    current = get_round(team, stage)
    policy = resolve_policy(team, stage, current=current)
    from repository.section_concepts.services import can_edit_module_titles, module_title_metadata, require_active
    if current.section_round_id:
        require_active(current.section_round.project)
        if not can_edit_module_titles(actor, team, stage, current):
            raise PermissionError('Faculty controls confirmed module names; the team leader may propose unconfirmed names.')
    if policy.get('mode') == 'assigned':
        raise PermissionError('Assigned project/module titles are managed in Manage sections.')
    if current.schedule_id or current.verdict:
        raise PermissionError('Scheduled concept titles are locked. Prepare changes in the next attempt.')
    if not isinstance(concepts, list) or len(concepts) != len(current.concepts):
        raise ValueError('Enter the configured number of concept titles.')
    keyed = {c.get('key'): c for c in concepts if isinstance(c, dict)}
    if len(keyed) != len(current.concepts) or set(keyed) != {c['key'] for c in current.concepts}:
        raise ValueError('Enter each configured concept exactly once.')
    updated = deepcopy(current.concepts)
    selected_key = current.section_round.selected_key if current.section_round_id else ''
    for c in updated:
        title = keyed.get(c['key'], {}).get('title', '')
        if not isinstance(title, str) or not title.strip() or len(title.strip()) > 255:
            raise ValueError('Every concept needs a title of up to 255 characters.')
        if selected_key and c['key'] != selected_key:
            if title.strip() != c['title']:
                raise ValidationError('Only the module linked to the selected section system can be changed.')
            continue
        metadata = module_title_metadata(actor, team, stage)
        if metadata.get('faculty_confirmed') and (not c.get('faculty_confirmed') or c['title'] != title.strip()):
            c.update(faculty_confirmed_by=actor.pk, faculty_confirmed_at=timezone.now().isoformat())
        c['title'] = title.strip()
        c.update(metadata)
    if updated != current.concepts:
        previous = deepcopy(current.concepts)
        invalidate_clearance(team, stage.label)
        current.concepts = updated
        current.save(update_fields=['concepts'])
        if current.section_round_id and actor and any(c.get('faculty_confirmed') for c in updated):
            log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
                action='repository.module_names_confirmed', target=current, actor=actor,
                reason='Reviewed module names and their shared system connections.',
                old_values={'concepts': previous}, new_values={'concepts': updated}, strict=True)
        if not team.current_defense_stage:
            team.current_defense_stage = stage.label
            team.save(update_fields=['current_defense_stage', 'updated_at'])
    return current


@transaction.atomic
def override_clearance(team, stage, actor, reason):
    from student_teams.models import StudentTeam
    from .services import get_deliverable_definitions_for_team, submissions_for, required_complete
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    if not (actor.is_superuser or actor.role == 'admin'):
        raise PermissionError('Only an administrator can override adviser clearance.')
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError('Record the reason for overriding adviser clearance.')
    current = get_round(team, stage)
    if current.schedule_id or not titles_complete(current):
        raise ValueError('Complete an unscheduled concept set before overriding clearance.')
    if not required_complete(team, stage.label):
        raise ValueError('Accept every required pre-defense file before endorsing the team.')
    submitted = submissions_for(team, stage.label)
    for d in get_deliverable_definitions_for_team(team, stage.label):
        if d['required'] and d['type'] == 'pre' and d.get('requirement_timing') != 'defense' and not completeness(submitted.get(d['id']), d, stage=stage):
            raise ValueError('Required documents must be uploaded and corrections resolved before overriding clearance.')
    endorse(team, stage, actor)
    current.refresh_from_db()
    current.override_reason = reason.strip()
    current.save(update_fields=['override_reason'])
    if team.is_capstone:
        from student_teams.services import mark_stage_ready
        mark_stage_ready(team, stage, user=actor)
    else:
        team.ready_for_stage = stage.label
        team.save(update_fields=['ready_for_stage', 'updated_at'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
        action='repository.concept_clearance_override', target=current, actor=actor,
        reason=reason.strip(), new_values={'team_id': team.pk, 'round': current.number}, strict=True)


def payload(team, stage, *, history=True, actor=None):
    if not enabled(stage):
        return None
    require_context(team, stage)
    rounds = list(ConceptRound.objects.filter(team=team, **context_fields(stage),
        project_version=team.project_version).order_by('-number', '-pk'))
    current = rounds[0] if rounds else None
    policy = resolve_policy(team, stage, current=current)
    concepts = current.concepts if current else initial_concepts(policy)
    shared_policy = policy.get('source') == 'section_system'
    shared_round = current.section_round if current and current.section_round_id else None
    shared_review = None
    if shared_policy:
        from repository.section_concepts.models import SectionConceptRound
        shared_round = shared_round or SectionConceptRound.objects.filter(pk=policy.get('section_round_id')).first()
        from repository.section_concepts.services import review_summary
        shared_review = review_summary(shared_round, team=team) if shared_round else None
        names = {s.key: s.title for s in shared_round.systems.all()} if shared_round else {}
        concepts = [{**c, 'system_title': names.get(c['key'], ''),
            'section_selected': bool(shared_round and shared_round.selected_key == c['key'])} for c in concepts]
    from .services import required_complete
    ready = not clearance_blocker(team, stage)
    if current and current.schedule_id:
        status = current.verdict or 'scheduled'
    elif not titles_complete(current):
        status = ('concept_review_pending' if policy.get('mode') == 'assigned' and policy.get('assigned_title') else
                  'replacement_concepts_needed' if current and current.number > 1 else 'concepts_needed')
    elif ready:
        status = 'ready_to_schedule_redefense' if current and current.number > 1 else 'ready_to_schedule'
    elif shared_policy and not all(c.get('faculty_confirmed') for c in concepts):
        status = 'module_confirmation_pending'
    elif shared_review and clearance_valid(team, stage, current) and not shared_review['cleared']:
        status = 'shared_clearance_pending'
    elif shared_review and clearance_valid(team, stage, current) and not shared_review['acknowledged']:
        status = 'shared_acknowledgment_pending'
    elif required_complete(team, stage.label):
        status = 'concept_endorsement_pending'
    else:
        status = 'concept_review_pending'
    from .pit_decisions import decision_payload
    return {'enabled': True, 'config': policy, 'round': current.number if current else 1,
        'selection_mode': 'shared_module' if shared_policy else 'team_concept',
        'shared_selection': ({'selected_key': shared_round.selected_key,
            'system_title': next((c.get('system_title', '') for c in concepts
                                 if c['key'] == shared_round.selected_key), ''),
            'module': next((c for c in concepts if c['key'] == shared_round.selected_key), None),
            'decision': shared_round.verdict,
            'revisions_pending': shared_round.verdict == 'approved_with_revisions' and not shared_round.revisions_cleared_at}
            if shared_round else None),
        **(decision_payload(team, stage, current, actor) if team.is_pit else {}),
        'module_review_token': module_review_token(team, stage),
        'section_project_id': policy.get('section_project_id'),
        'shared_review': shared_review,
        'section_selected_key': shared_round.selected_key if shared_round else '',
        'section_presenting': bool(shared_round and shared_round.presentation_started_at),
        'section_revisions_pending': bool(shared_round and shared_round.verdict == 'approved_with_revisions' and not shared_round.revisions_cleared_at),
        'faculty_names_required': shared_policy and policy.get('title_mode') == 'faculty_provided',
        'module_names_confirmed': shared_policy and all(c.get('faculty_confirmed') for c in concepts),
        'module_names_confirmed_count': sum(bool(c.get('faculty_confirmed')) for c in concepts),
        'concepts': concepts, 'status': status, 'can_edit': bool(team.semester.is_active and (not current or not current.schedule_id)),
        'assigned': policy.get('mode') == 'assigned',
        'can_edit_titles': policy.get('mode') != 'assigned' and bool(team.semester.is_active and (not current or not current.schedule_id)),
        'clearance_valid': clearance_valid(team, stage, current),
        'review_required': current.review_required if current else True,
        'next_step': ('The administrator must assign the replacement project/module in Manage sections.'
            if policy.get('mode') == 'assigned' and not policy.get('assigned_title') else {
            'concepts_needed': 'Upload the paper for your assigned project/module.' if policy.get('mode') == 'assigned' else 'Enter concept titles and upload the required papers.',
            'replacement_concepts_needed': 'Submit replacement concepts using the panel feedback.',
            'concept_review_pending': f'Upload missing documents and have the {reviewer_name(stage)} review the current papers.',
            'concept_endorsement_pending': f'The {reviewer_name(stage)} needs to endorse the reviewed concept set.',
            'module_confirmation_pending': 'Review and confirm the module names and their shared system connections.',
            'shared_clearance_pending': 'Team endorsed. Waiting for the required shared papers to be accepted.',
            'shared_acknowledgment_pending': 'Team endorsed. The assigned adviser/instructor needs to review and acknowledge the current shared proposals.',
            'ready_to_schedule': f'The {"PIT Lead" if team.is_pit else "administrator"} can schedule the concept hearing.',
            'ready_to_schedule_redefense': f'The {"PIT Lead" if team.is_pit else "administrator"} can schedule the next defense attempt.',
            'scheduled': 'Prepare for the scheduled concept hearing.'}.get(status, 'Review the recorded outcome and stage requirements.')),
        'history': [{'round': r.number, 'schedule_id': r.schedule_id, 'verdict': r.verdict, 'policy': r.policy_snapshot,
            'decided_at': r.decided_at.isoformat() if r.decided_at else None,
            'decided_by_name': (r.decided_by.get_full_name() or r.decided_by.username) if r.decided_by else '',
            'remarks': r.remarks, 'concepts': r.concepts, 'documents': r.documents_snapshot,
            'override_reason': r.override_reason} for r in rounds if r.schedule_id or r.verdict] if history else []}


def summary(team, stage):
    """Compact triage facts; scheduling always uses the full clearance guard."""
    if not enabled(stage):
        return None
    current = latest_round(team, stage)
    policy = resolve_policy(team, stage, current=current)
    number = current.number if current else 1
    if current and current.schedule_id:
        status = current.verdict or 'scheduled'
    elif not titles_complete(current):
        status = ('concept_review_pending' if policy.get('mode') == 'assigned' and policy.get('assigned_title') else
                  'replacement_concepts_needed' if number > 1 else 'concepts_needed')
    elif current.section_round_id and not all(c.get('faculty_confirmed') for c in current.concepts):
        status = 'module_confirmation_pending'
    elif current.endorsed_at:
        from repository.section_concepts.services import review_summary
        shared = review_summary(current.section_round, team=team) if current.section_round_id else None
        status = ('shared_clearance_pending' if shared and not shared['cleared'] else
                  'shared_acknowledgment_pending' if shared and not shared['acknowledged'] else
                  'ready_to_schedule_redefense' if number > 1 else 'ready_to_schedule')
    else:
        from .services import required_complete
        if not current.review_required and not clearance_blocker(team, stage):
            status = 'ready_to_schedule_redefense' if number > 1 else 'ready_to_schedule'
        else:
            status = 'concept_endorsement_pending' if required_complete(team, stage.label) else 'concept_review_pending'
    return {'enabled': True, 'round': number, 'status': status,
        'section_project_id': policy.get('section_project_id'),
        'system_concepts': policy.get('system_concepts', []),
        'concepts': [{k: c.get(k, '') for k in ('key', 'title', 'decision')}
            for c in (current.concepts if current else initial_concepts(policy))],
        'assigned': policy.get('mode') == 'assigned', 'required_count': policy['required_count'],
        'can_edit': bool(team.semester.is_active and (not current or not current.schedule_id)),
        'next_step': {
            'replacement_concepts_needed': 'The administrator assigns the replacement project/module.' if policy.get('mode') == 'assigned' else 'Students submit replacement concept titles and papers.',
            'concepts_needed': 'Students submit the required concepts.',
            'concept_review_pending': f'The {reviewer_name(stage)} reviews the current concept papers.',
            'concept_endorsement_pending': f'The {reviewer_name(stage)} endorses the reviewed concept set.',
            'module_confirmation_pending': 'Review and confirm the module names and shared system connections.',
            'shared_clearance_pending': 'Team endorsed. Waiting for shared paper acceptance.',
            'shared_acknowledgment_pending': 'Team endorsed. The assigned faculty must acknowledge the current shared proposals.',
            'ready_to_schedule_redefense': f'The {"PIT Lead" if team.is_pit else "administrator"} schedules the next defense attempt.',
            'ready_to_schedule': f'The {"PIT Lead" if team.is_pit else "administrator"} schedules the concept hearing.',
            'scheduled': 'The team prepares for its scheduled concept hearing.',
        }.get(status, 'Review the recorded outcome and remaining stage requirements.')}
