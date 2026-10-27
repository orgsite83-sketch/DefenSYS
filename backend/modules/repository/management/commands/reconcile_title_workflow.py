"""Explicit, snapshot-checked upgrade of editable legacy proposals.

The default is a read-only preflight. Scheduled/history evidence is never changed.
"""
import json
from copy import deepcopy
from hashlib import sha256

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from repository import title_workflow as workflow
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound, DeliverableSubmissionFile
from repository.section_concepts import services
from repository.section_concepts.models import SectionConceptRound, SharedDeliverableFile, SectionConceptPaper


class Command(BaseCommand):
    help = 'Preview an editable title-workflow upgrade; --apply requires the reviewed token and an admin actor.'

    def add_arguments(self, parser):
        group = parser.add_mutually_exclusive_group(required=True)
        group.add_argument('--section-round', type=int)
        group.add_argument('--team-round', type=int)
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--token')
        parser.add_argument('--actor', type=int)

    @transaction.atomic
    def handle(self, *args, **options):
        section = None
        if options['section_round']:
            section = SectionConceptRound.objects.select_for_update().get(pk=options['section_round'])
            services.require_active(section.project)
            services.editable(section)
            if services.latest(section.project).pk != section.pk:
                raise CommandError('Only the current section round can be upgraded.')
            rounds = list(section.module_rounds.select_for_update().order_by('pk'))
        else:
            rounds = [ConceptRound.objects.select_for_update().get(pk=options['team_round'])]
            if rounds[0].section_round_id:
                raise CommandError('Reconcile the shared section round together with its linked teams.')
        for current in rounds:
            stage = current.pit_event_config or current.defense_stage
            if (not concepts.title_context_is_open(current.team, stage) or current.schedule_id or current.verdict
                    or concepts.latest_round(current.team, stage).pk != current.pk):
                raise CommandError('Scheduled, decided and historical rounds cannot be upgraded.')
        systems = list(section.systems.select_for_update().order_by('key')) if section else []
        files = []
        for current in rounds:
            stage = current.pit_event_config or current.defense_stage
            files.extend(DeliverableSubmissionFile.objects.select_for_update().filter(
                submission__team=current.team, submission__project_version=current.project_version,
                submission__stage_label=stage.label, is_current=True, slot_key__contains=':'))
        if section:
            files.extend(SectionConceptPaper.objects.select_for_update().filter(concept__round=section, is_current=True, purpose='proposal'))
            files.extend(SharedDeliverableFile.objects.select_for_update().filter(submission_set__source_round=section,
                submission_set__requirements__isnull=False, is_current=True, slot_key__contains=':'))
        state = {'section_round': section.pk if section else None,
            'systems': [{'key': s.key, 'title': s.title, 'confirmed': s.confirmed, 'review': s.title_review} for s in systems],
            'teams': [{'round': r.pk, 'team': r.team_id, 'version': r.title_workflow_version, 'concepts': r.concepts,
                       'endorsed_at': str(r.endorsed_at)} for r in rounds],
            'files': [{'kind': type(f).__name__, 'id': f.pk, 'status': f.status,
                       'revision': f.revision, 'context': f.title_review_context} for f in files]}
        token = sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()
        self.stdout.write(json.dumps({'preflight': state, 'token': token,
            'effects': 'Confirmed legacy titles retain acceptance with legacy provenance, without invented reviewers. Other titles require student submission. Compatible accepted files retain their evidence. Stale accepted files require re-review. Unscheduled endorsements are cleared.'}, indent=2))
        if not options['apply']:
            return
        if options['token'] != token:
            raise CommandError('Preflight changed. Review a fresh preflight token.')
        actor = get_user_model().objects.filter(pk=options['actor'], is_active=True).first()
        if not actor or not (actor.role == 'admin' or actor.is_superuser):
            raise CommandError('--apply requires an active admin --actor.')
        if section and section.title_workflow_version >= 2 or not section and all(workflow.enabled(r) for r in rounds):
            raise CommandError('This proposal already uses title-first review.')
        for system in systems:
            system.title_review = {'state': 'accepted' if system.confirmed and system.title.strip() else 'draft',
                'version': 1 if system.confirmed else 0, 'evidence': workflow.evidence(system.title),
                'provenance': 'legacy_confirmation', 'parent': {}}
            system.save(update_fields=['title_review'])
        if section:
            section.title_workflow_version = 2
            section.save(update_fields=['title_workflow_version'])
        for current in rounds:
            for item in current.concepts:
                parent = workflow.parent_for(current, item['key'])
                confirmed = bool(item.get('faculty_confirmed') and item.get('title', '').strip())
                item['title_review'] = {'state': 'accepted' if confirmed else 'draft', 'version': 1 if confirmed else 0,
                    'parent': workflow.parent_evidence(parent), 'evidence': workflow.evidence(item.get('title', ''), workflow.parent_evidence(parent)),
                    'provenance': 'legacy_confirmation' if confirmed else 'legacy_seed'}
            current.title_workflow_version = 2
            current.save(update_fields=['title_workflow_version', 'concepts'])
            concepts.invalidate_clearance(current.team, (current.pit_event_config or current.defense_stage).label)
        for file in files:
            try:
                if isinstance(file, DeliverableSubmissionFile):
                    current = next(r for r in rounds if r.team_id == file.submission.team_id)
                    context = workflow.team_guard(current.team, current.pit_event_config or current.defense_stage,
                        file.slot_key.split(':')[0], accepting=True)
                else:
                    key = file.concept.key if isinstance(file, SectionConceptPaper) else file.slot_key.split(':')[0]
                    system = next((s for s in systems if s.key == key), None)
                    context = workflow.system_guard(system, accepting=True) if system else {}
                file.title_review_context = context
                file.save(update_fields=['title_review_context'])
            except Exception as exc:
                from django.core.exceptions import ValidationError
                if not isinstance(exc, ValidationError):
                    raise
                if file.status == 'accepted':
                    file.status = 'pending'
                    file.save(update_fields=['status'])
        if section:
            services.invalidate(section, modules=True)
        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY, action='repository.title_workflow_reconciled',
            target=section or rounds[0], actor=actor, reason='Applied the reviewed title-first preflight.',
            old_values=deepcopy(state), new_values={'version': 2, 'preflight_token': token}, strict=True)
        self.stdout.write(self.style.SUCCESS('Title-first workflow applied. Stored hearing history and file bytes were retained.'))
