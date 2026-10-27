"""Title-first proposal review. Reads project state; only explicit actions write it.

Legacy hearing evidence stays on v1 until an explicit, audited reconciliation.
Title content fingerprints intentionally survive an unchanged resubmission.
"""
from copy import deepcopy
from hashlib import sha256
import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

LABELS = {'draft': 'Awaiting student submission', 'submitted': 'Awaiting title review',
          'changes_requested': 'Title revision requested', 'accepted': 'Title accepted'}
NEXT_STEPS = {
    'draft': 'The student submits the proposed title. A concept paper is optional at this step.',
    'submitted': 'The assigned adviser reviews the submitted title in Concept review.',
    'changes_requested': 'Revise and resubmit the title using the adviser feedback.',
}


def enabled(round):
    return bool(round and round.title_workflow_version >= 2)


def new_version():
    from django.conf import settings
    return getattr(settings, 'DEFENSYS_TITLE_WORKFLOW_VERSION', 2)


def version_for_policy(policy):
    if policy.get('section_round_id'):
        from repository.section_concepts.models import SectionConceptRound
        return SectionConceptRound.objects.get(pk=policy['section_round_id']).title_workflow_version
    return new_version()


def evidence(title, parent=None):
    return {'title': title.strip(), 'parent': parent or {}}


def fingerprint(value):
    return sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def parent_for(current, key):
    if not current or not current.section_round_id:
        return None
    return current.section_round.systems.filter(key=key).first()


def parent_evidence(parent):
    if not parent:
        return {}
    return {'id': parent.pk, 'title': parent.title, 'version': parent.title_review.get('version', 0)}


def accepted(item, parent=None):
    review = item.get('title_review') or {}
    return bool(review.get('state') == 'accepted' and item.get('title', '').strip()
        and (not parent or review.get('parent') == parent_evidence(parent)))


def accepted_system(system):
    return bool(system.title.strip() and system.title_review.get('state') == 'accepted')


def reviewer(actor, team):
    from repository.deliverables.views import check_deliverable_write_permission
    return bool(actor and actor.role != 'student' and check_deliverable_write_permission(actor, team))


def request_payload(pk):
    from repository.deliverables.models import ConceptRevisionRequest
    row = ConceptRevisionRequest.objects.filter(pk=pk).select_related('requested_by').first() if pk else None
    return ({'id': row.pk, 'scope': row.scope, 'feedback': row.feedback,
        'requested_at': row.requested_at.isoformat(), 'file_id': row.file_id,
        'requested_by_name': row.requested_by.get_full_name() or row.requested_by.username} if row else None)


def legacy_review(item, *, saved=False, confirmed=False, parent=None):
    """Present existing saved titles without migrating or inventing review actors."""
    return deepcopy(item.get('title_review') or {
        'state': 'accepted' if confirmed else 'submitted' if saved and item.get('title', '').strip() else 'draft',
        'version': 0, 'parent': parent_evidence(parent),
        'evidence': evidence(item.get('title', ''), parent_evidence(parent)),
        'provenance': 'legacy_title',
    })


def present(item, *, can_submit=False, can_review=False, editable=True, parent=None, assigned=False):
    data = deepcopy(item.get('title_review') or {'state': 'draft', 'version': 0})
    state = data.get('state', 'draft')
    blocker = ''
    if parent and data.get('state') in ('submitted', 'accepted') and data.get('parent') != parent_evidence(parent):
        state, blocker = 'changes_requested', 'The shared system changed. Resubmit the module connection for review.'
    if not editable:
        blocker = 'This scheduled, decided or historical proposal is read-only.'
    data.update(state=state, status_label=LABELS.get(state, state), blocker=blocker,
        can_submit=bool(editable and can_submit and state in ('draft', 'changes_requested')),
        can_edit=bool(editable and can_submit and not assigned and state in ('draft', 'changes_requested')),
        can_accept=bool(editable and can_review and not blocker and state == 'submitted'),
        can_request_revision=bool(editable and can_review and not blocker and state in ('submitted', 'accepted')),
        revision_request=request_payload(data.get('request_id')))
    if assigned:
        data['edit_reason'] = 'This assigned title is maintained in Manage sections. The leader submits it for adviser review.'
    return data


def team_payload(team, stage, current, items, actor, policy):
    from repository.deliverables.concepts import title_context_is_open
    open_now = title_context_is_open(team, stage) and not (current and (current.schedule_id or current.verdict))
    result = []
    for item in items:
        parent = parent_for(current, item['key'])
        if parent is None and policy.get('section_round_id'):
            from repository.section_concepts.models import SectionSystemConcept
            parent = SectionSystemConcept.objects.filter(round_id=policy['section_round_id'], key=item['key']).first()
        row = deepcopy(item)
        if current and not enabled(current):
            row['title_review'] = legacy_review(item, saved=True,
                confirmed=item.get('faculty_confirmed', False), parent=parent)
        if parent:
            row['system_title'] = parent.title
        row['title_review'] = present(row, can_submit=bool(actor and actor.role == 'student' and team.leader_id == actor.pk),
            can_review=reviewer(actor, team), editable=open_now, parent=parent, assigned=policy.get('mode') == 'assigned')
        row['faculty_confirmed'] = accepted(row, parent)
        result.append(row)
    return result


def next_status(items):
    states = [c['title_review']['state'] for c in items]
    for state in ('changes_requested', 'submitted', 'draft'):
        if state in states:
            return state, LABELS[state]
    return 'titles_accepted', 'Titles accepted'


def new_review(old, title, parent, actor):
    context = evidence(title, parent)
    return {**old, 'state': 'submitted', 'version': max(1, old.get('version', 0) + int(old.get('evidence') != context)),
        'evidence': context, 'parent': parent or {}, 'submitted_by': actor.pk,
        'submitted_at': timezone.now().isoformat(), 'reviewed_by': None, 'reviewed_at': None}


def _request(current, key, review, actor, reason, *, scope='title', file=None, kind=''):
    from repository.deliverables.models import ConceptRevisionRequest
    if not reason.strip():
        raise ValidationError('Explain what needs to change.')
    # Repeated HTTP requests with the same current identities reuse one logical request.
    existing = ConceptRevisionRequest.objects.filter(pk=review.get('request_id')).first()
    if (review.get('state') == 'changes_requested' and existing and existing.scope == scope
            and existing.file_id == getattr(file, 'pk', None) and existing.feedback == reason.strip()):
        return existing
    if review.get('state') not in ('submitted', 'accepted'):
        raise ValidationError('Only a submitted or accepted title can be returned for revision.')
    shared = current.__class__.__name__ == 'SectionConceptRound'
    snapshot = deepcopy(review)
    if file:
        snapshot['file'] = {'id': file.pk, 'revision': file.revision, 'kind': kind,
            'file_name': file.file_name, 'context': file.title_review_context}
    row = ConceptRevisionRequest.objects.create(scope=scope, concept_key=key,
        **({'section_round': current} if shared else {'concept_round': current}),
        file_kind=kind, file_id=getattr(file, 'pk', None), title_snapshot=snapshot,
        feedback=reason.strip(), requested_by=actor)
    review.update(state='changes_requested', request_id=row.pk, reviewed_by=actor.pk,
        reviewed_at=timezone.now().isoformat())
    return row


@transaction.atomic
def team_action(team, stage, actor, action, key, title=None, reason=''):
    from student_teams.models import StudentTeam
    from repository.deliverables import concepts
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    current = concepts.latest_round(team, stage)
    if action in ('submit_title', 'draft_title') and actor.role == 'student' and team.leader_id == actor.pk:
        current = current or concepts.get_round(team, stage)
    if not current:
        raise ValidationError('The team leader must save or submit this title in Team first.')
    if not concepts.title_context_is_open(team, stage) or current.schedule_id or current.verdict:
        raise PermissionError('Scheduled, decided and historical titles are read-only.')
    values = deepcopy(current.concepts)
    item = next((c for c in values if c['key'] == key), None)
    if item is None:
        raise ValidationError('Choose a title from the current concept set.')
    parent = parent_for(current, key)
    if not enabled(current):
        item['title_review'] = legacy_review(item, saved=True,
            confirmed=item.get('faculty_confirmed', False), parent=parent)
    review = item.setdefault('title_review', {'state': 'draft', 'version': 0})
    if action in ('submit_title', 'draft_title'):
        if actor.role != 'student' or team.leader_id != actor.pk:
            raise PermissionError('Only the team leader can submit this title.')
        parent_changed = parent and review.get('parent') != parent_evidence(parent)
        if review['state'] not in ('draft', 'changes_requested') and not parent_changed:
            raise ValidationError('Request a title revision before changing a submitted or accepted title.')
        title = item.get('title', '') if title is None else title.strip()
        if current.policy_snapshot.get('mode') == 'assigned' and title != item.get('title', ''):
            raise PermissionError('Assigned titles are maintained in Manage sections.')
        if not title or len(title) > 255:
            raise ValidationError('Enter a title of up to 255 characters.')
        item['title'] = title
        if action == 'submit_title':
            item['title_review'] = new_review(review, title, parent_evidence(parent), actor)
            if review.get('evidence') and review['evidence'] != item['title_review']['evidence']:
                from repository.deliverables.concepts import invalidate_module_title_reviews
                invalidate_module_title_reviews(team, stage, current, {key}, actor)
    else:
        if not reviewer(actor, team):
            raise PermissionError('Only the assigned adviser/instructor can review this title.')
        if action == 'accept_title':
            if review['state'] != 'submitted' or (parent and review.get('parent') != parent_evidence(parent)):
                raise ValidationError('Review the submitted title for the current shared system.')
            review.update(state='accepted', reviewed_by=actor.pk, reviewed_at=timezone.now().isoformat())
            item.update(faculty_confirmed_by=actor.pk, faculty_confirmed_at=review['reviewed_at'])
        elif action == 'request_title_revision':
            _request(current, key, review, actor, reason)
        else:
            raise ValidationError('Choose a supported title action.')
    item['faculty_confirmed'] = accepted(item, parent)
    current.concepts = values
    current.save(update_fields=['concepts'])
    concepts.invalidate_clearance(team, stage.label)
    from repository.section_concepts.services import audit
    audit(actor, action, current, key=key, title=item['title'], reason=reason)
    return current


@transaction.atomic
def system_action(project, actor, action, key, title=None, reason=''):
    from repository.section_concepts import services
    services.require_active(project)
    current = services.locked_round(project)
    services.editable(current)
    item = current.systems.select_for_update().get(key=key)
    review = (deepcopy(item.title_review or {'state': 'draft', 'version': 0}) if enabled(current)
              else legacy_review({'title': item.title, 'title_review': item.title_review},
                  saved=True, confirmed=item.confirmed))
    if action in ('submit_title', 'draft_title'):
        if not services.is_pm(actor, project):
            raise PermissionError('Only the designated project manager can submit system titles.')
        if review['state'] not in ('draft', 'changes_requested'):
            raise ValidationError('Request revision before changing a submitted or accepted system title.')
        proposed = item.title if title is None else title.strip()
        if project.title_mode == 'faculty_provided' and proposed != item.title:
            raise PermissionError('Assigned titles are maintained by the section administrator.')
        if not proposed or len(proposed) > 255:
            raise ValidationError('Enter a title of up to 255 characters.')
        item.title = proposed
        if action == 'submit_title':
            previous = review.get('evidence')
            review = new_review(review, proposed, {}, actor)
            if previous and previous != review['evidence']:
                from repository.section_concepts.shared_deliverables import invalidate_title_reviews
                invalidate_title_reviews(current, {key}, actor)
                item.papers.filter(is_current=True, status='accepted', purpose='proposal').update(status='pending')
    else:
        if not services.is_reviewer(actor, project):
            raise PermissionError('Only an assigned shared-system reviewer can review this title.')
        if action == 'accept_title':
            if review['state'] != 'submitted':
                raise ValidationError('Wait for the project manager to submit this system title.')
            review.update(state='accepted', reviewed_by=actor.pk, reviewed_at=timezone.now().isoformat())
        elif action == 'request_title_revision':
            _request(current, key, review, actor, reason)
        else:
            raise ValidationError('Choose a supported title action.')
    item.title_review = review
    item.confirmed = accepted_system(item)
    item.save(update_fields=['title', 'title_review', 'confirmed'])
    services.invalidate(current, modules=True)
    services.audit(actor, action, current, key=key, title=item.title, reason=reason)
    return item


def team_guard(team, stage, key, *, accepting=False):
    from repository.deliverables.concepts import latest_round, enabled as concepts_enabled
    current = latest_round(team, stage)
    if current is None and concepts_enabled(stage):
        raise ValidationError('Submit the matching concept/module title in Team before uploading its file.')
    if not enabled(current):
        if current and not accepting:
            item = next((c for c in current.concepts if c['key'] == key), None)
            if not item or not item.get('title', '').strip():
                raise ValidationError('Save the matching concept/module title in Team before uploading its file.')
            review = item.get('title_review') or {}
            if review and review.get('state') not in ('submitted', 'accepted'):
                raise ValidationError('Resubmit the matching title in Team before uploading its file.')
        return {}
    item = next((c for c in current.concepts if c['key'] == key), None)
    if not item:
        raise ValidationError('Choose the matching concept title.')
    parent = parent_for(current, key)
    if (parent and (item.get('title_review') or {}).get('state') in ('submitted', 'accepted')
            and (item.get('title_review') or {}).get('parent') != parent_evidence(parent)):
        raise ValidationError('Resubmit this module title for the current shared system before uploading or reviewing its file.')
    if accepting and not accepted(item, parent):
        raise ValidationError('Accept this concept/module title in Concept review before accepting its file.')
    if not accepting and (not item.get('title', '').strip() or item.get('title_review', {}).get('state') not in ('submitted', 'accepted')):
        raise ValidationError('Submit the matching concept/module title in Team before uploading its file.')
    return evidence(item['title'], parent_evidence(parent))


def system_guard(system, *, accepting=False):
    if not enabled(system.round):
        return {}
    if accepting and not accepted_system(system):
        raise ValidationError('Accept this shared system title in Concept review before accepting its file.')
    if not accepting and system.title_review.get('state') not in ('submitted', 'accepted'):
        raise ValidationError('Submit this shared system title before uploading its file.')
    return evidence(system.title)


def file_acceptance(file, context):
    from repository.deliverables.models import ConceptRevisionRequest
    if not context:
        return
    if file.title_review_context != context:
        raise ValidationError('This file belongs to an earlier title or system version. Upload an updated file after title review.')
    kind = 'team' if file.__class__.__name__ == 'DeliverableSubmissionFile' else 'legacy' if file.__class__.__name__ == 'SectionConceptPaper' else 'shared'
    if ConceptRevisionRequest.objects.filter(file_id=file.pk, file_kind=kind, scope__in=['paper', 'title_and_paper']).exists():
        raise ValidationError('Upload the requested new file revision before accepting it.')


def revise_file(current, key, actor, reason, file, scope, kind):
    """Caller holds team/project and file locks in the enclosing transaction."""
    from repository.deliverables.models import ConceptRevisionRequest
    if scope not in ('paper', 'title_and_paper'):
        raise ValidationError('Choose Paper only or Title and paper.')
    if not reason.strip():
        raise ValidationError('Explain the requested revision.')
    shared = current.__class__.__name__ == 'SectionConceptRound'
    item = current.systems.select_for_update().get(key=key) if shared else next((c for c in current.concepts if c['key'] == key), None)
    if not item:
        raise ValidationError('The matching title was not found.')
    review = deepcopy(item.title_review) if shared else item.setdefault('title_review', {})
    if scope == 'title_and_paper':
        row = _request(current, key, review, actor, reason, scope=scope, file=file, kind=kind)
        if shared:
            item.title_review, item.confirmed = review, False
            item.save(update_fields=['title_review', 'confirmed'])
            from repository.section_concepts.services import invalidate
            invalidate(current, modules=True)
        else:
            item['faculty_confirmed'] = False
            current.save(update_fields=['concepts'])
    else:
        snapshot = deepcopy(review)
        snapshot['file'] = {'id': file.pk, 'revision': file.revision, 'kind': kind,
            'file_name': file.file_name, 'context': file.title_review_context}
        row = ConceptRevisionRequest.objects.filter(file_kind=kind, file_id=file.pk,
            scope='paper', feedback=reason.strip()).first()
        row = row or ConceptRevisionRequest.objects.create(scope='paper', concept_key=key,
            **({'section_round': current} if shared else {'concept_round': current}),
            file_kind=kind, file_id=file.pk, title_snapshot=snapshot, feedback=reason.strip(), requested_by=actor)
    return row


def shared_system(profile, definition, key):
    if definition['deliverable_type'] != 'pre' or not enabled(profile.get('round')):
        return None
    from repository.section_concepts.shared_deliverables import slots
    slot = next((s for s in slots(profile, definition) if s['key'] == key), {})
    system_key = slot.get('system_key')
    return profile['round'].systems.filter(key=system_key).first() if system_key else None


def shared_context(profile, definition, key, *, accepting=False):
    system = shared_system(profile, definition, key)
    return system_guard(system, accepting=accepting) if system else {}
