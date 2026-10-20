"""Clear orphaned display decisions after an explicitly requested hearing reset.

This is deliberately not a hearing reset: it cannot remove schedules, grades,
recorded verdicts, papers, reviews, or endorsements.
"""
from django.core.exceptions import PermissionDenied
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from repository.section_concepts import services
from repository.section_concepts.models import SectionConceptProject, SectionConceptRound


class Command(BaseCommand):
    help = 'Preview or clear stale system labels on an otherwise fully reset, unscheduled shared round.'

    def add_arguments(self, parser):
        parser.add_argument('--project-id', type=int, required=True)
        parser.add_argument('--round-id', type=int, required=True)
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--reason', default='')

    @transaction.atomic
    def handle(self, *args, **options):
        if options['apply'] and not options['reason'].strip():
            raise CommandError('--apply requires a reason for the audit record.')
        try:
            project = SectionConceptProject.objects.select_for_update().get(pk=options['project_id'])
        except SectionConceptProject.DoesNotExist as exc:
            raise CommandError('Section project does not exist.') from exc
        try:
            services.require_active(project)
        except (PermissionError, PermissionDenied) as exc:
            raise CommandError(str(exc)) from exc
        current = SectionConceptRound.objects.select_for_update().filter(project=project).order_by('-number', '-pk').first()
        if not current or current.pk != options['round_id']:
            raise CommandError('Choose the current round explicitly; historical rounds cannot be repaired.')
        if any((current.selected_key, current.verdict, current.presentation_started_at,
                current.presentation_started_by_id, current.decided_at, current.decided_by_id,
                current.decision_snapshot, current.chair_id, current.remarks,
                current.revisions_cleared_at, current.revisions_cleared_by_id, current.revision_notes)):
            raise CommandError('The hearing still has presentation or decision evidence. No labels were changed.')
        links = list(services.active_links(project))
        if not links or current.schedules.exists():
            raise CommandError('The round must have participating teams and no attached schedules.')
        modules = list(current.module_rounds.select_for_update())
        expected = {(link.team_id, link.project_version) for link in links}
        if {(m.team_id, m.project_version) for m in modules} != expected or len(modules) != len(expected):
            raise CommandError('Current team links and module rounds do not match. Review the reset manually.')
        for module in modules:
            if any((module.schedule_id, module.verdict, module.decided_at, module.decided_by_id,
                    module.revisions_cleared_at, module.revisions_cleared_by_id,
                    module.replacement_required, module.remarks)) or any(
                        c.get('decision') or c.get('remarks') for c in module.concepts):
                raise CommandError('A module still has a schedule or outcome. No labels were changed.')
        for link in links:
            # Fail closed even for another event: this repair never rewinds a live team.
            lookup = {'team_id': link.team_id, 'project_version': link.project_version}
            if DefenseSchedule.objects.filter(**lookup).exists() or TeamGrade.all_objects.filter(**lookup).exists():
                raise CommandError('A participating team still has schedule or grade records. No labels were changed.')
            if DeliverableSubmission.all_objects.filter(**lookup, stage_label=project.context.label,
                    deliverable_type='post').exists():
                raise CommandError('Post-defense submissions exist. Review their history before reconciling.')
        if current.systems.filter(papers__purpose='final').exists():
            raise CommandError('Shared final papers exist. Review their history before reconciling.')
        old = list(current.systems.select_for_update().order_by('key').values('id', 'key', 'decision', 'remarks'))
        stale = [s for s in old if s['decision'] or s['remarks']]
        if not stale:
            self.stdout.write('No stale system decisions. No changes needed.')
            return
        self.stdout.write(f'{"APPLY" if options["apply"] else "READY"} project {project.pk}, round {current.pk}: '
                          f'clear {len(stale)} stale system labels; preserve proposals, reviews and endorsements.')
        if not options['apply']:
            return
        current.systems.update(decision='', remarks='')
        context = {'scope': 'pit' if project.pit_event_config_id else 'capstone',
            'year_level': project.section.year_level, 'section': project.section.section,
            'team_ids': sorted(link.team_id for link in links), 'round_id': current.pk}
        audit = log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='section_concepts.unscheduled_system_labels_reconciled', target=current,
            reason=options['reason'].strip(), old_values={**context, 'systems': old},
            new_values={**context, 'systems': [{**s, 'decision': '', 'remarks': ''} for s in old]},
            strict=True)
        self.stdout.write(f'Updated only system decision labels. Audit record {audit.pk}.')
