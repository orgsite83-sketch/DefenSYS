"""Report missing concept final requirements; repair only unstarted configuration."""
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from defense.document_policy import with_concept_papers, is_approved_concept
from defense.scheduler.models import PitEventGradingConfig
from defense.scheduler.pit_config import check_pit_event_locked
from defense.stages.models import DefenseStage
from defense.stages.serializers import check_stage_locked
from repository.deliverables.models import DeliverableSubmission


class Command(BaseCommand):
    help = 'Report concept requirement differences. --apply updates only unstarted, unlocked setup and preserves IDs.'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--pit-event-id', type=int)
        parser.add_argument('--include-started', action='store_true', help='Explicitly add a missing final-paper definition to an active started event. Never rewrites captured definitions.')
        parser.add_argument('--reason', default='')

    def handle(self, *args, **options):
        if options['include_started'] and (not options['pit_event_id'] or not options['reason'].strip()):
            raise CommandError('Started-event reconciliation requires --pit-event-id and --reason.')
        changed = blocked = 0
        for model in (DefenseStage, PitEventGradingConfig):
            query = model.objects.filter(concept_config__enabled=True)
            if options['pit_event_id']:
                if model is DefenseStage:
                    continue
                query = query.filter(pk=options['pit_event_id'])
            for pk in query.values_list('pk', flat=True):
                with transaction.atomic():
                    context = model.objects.select_for_update().get(pk=pk)
                    definitions = list(context.deliverables.all().values())
                    normalized = with_concept_papers(definitions, context.concept_config)
                    if definitions == normalized:
                        continue
                    locked, reason = (check_pit_event_locked(context) if isinstance(context, PitEventGradingConfig)
                                      else check_stage_locked(context))
                    submissions = DeliverableSubmission.all_objects.filter(stage_label=context.label)
                    if isinstance(context, PitEventGradingConfig):
                        submissions = submissions.filter(team__semester=context.semester, team__year_level=context.year_level,
                            team__level__icontains='PIT')
                    else:
                        submissions = submissions.filter(team__level__icontains='Capstone')
                    original = {item['deliverable_id']: item for item in definitions}
                    added = [item for item in normalized if item['deliverable_id'] not in original]
                    explicit_addition = (options['include_started'] and isinstance(context, PitEventGradingConfig)
                        and context.semester.is_active and not context.is_officially_complete
                        and len(added) == 1 and is_approved_concept(added[0])
                        and all(item == original[item['deliverable_id']] for item in normalized if item['deliverable_id'] in original))
                    if (locked or submissions.exists()) and not explicit_addition:
                        blocked += 1
                        self.stdout.write(f'REVIEW {context._meta.label} {pk}: {reason or "Existing files must retain their captured requirements."}')
                        continue
                    changed += 1
                    self.stdout.write(f'{"APPLY" if options["apply"] else "READY"} {context._meta.label} {pk}: add/normalize required proposal and approved concept papers')
                    if not options['apply']:
                        continue
                    fields = {field.name for field in context.deliverables.model._meta.fields} - {'id', 'defense_stage', 'pit_event_config'}
                    for item in normalized:
                        if explicit_addition and item['deliverable_id'] in original:
                            continue
                        values = {name: value for name, value in item.items() if name in fields}
                        context.deliverables.update_or_create(deliverable_id=item['deliverable_id'], defaults=values)
                    from authentication_access_control.audit import log_high_impact_action
                    from authentication_access_control.models import SystemAuditLog
                    log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
                        action='repository.concept_requirements_reconciled', target=context,
                        reason=options['reason'].strip() or 'Normalized required concept documents for an unstarted configuration.',
                        old_values={'deliverable_ids': [d['deliverable_id'] for d in definitions]},
                        new_values={'deliverable_ids': [d['deliverable_id'] for d in normalized]}, strict=True)
        self.stdout.write(f'{changed} eligible configurations; {blocked} started configurations require explicit review. No existing files or outcomes changed.')
