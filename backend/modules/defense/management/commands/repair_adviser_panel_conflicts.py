"""Repair explicitly selected open panels through the normal audited operation."""
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Count, F, Q
from rest_framework.exceptions import APIException

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.scheduler.operations import OperationSerializer, execute_operation, _overlap


class Command(BaseCommand):
    help = 'Preview adviser/panel conflicts and choose available eligible replacements. Use --apply to save.'

    def add_arguments(self, parser):
        parser.add_argument('--schedule-ids', nargs='+', type=int, required=True)
        parser.add_argument('--actor', required=True, help='Username of the administrator recording this correction.')
        parser.add_argument('--apply', action='store_true')

    @transaction.atomic
    def handle(self, *args, **options):
        actor = get_user_model().objects.filter(username=options['actor'], is_active=True).first()
        if actor is None or not (actor.role == 'admin' or actor.is_superuser):
            raise CommandError('Choose an active administrator as the audit actor.')
        requested = set(options['schedule_ids'])
        schedules = list(DefenseSchedule.objects.select_for_update().filter(pk__in=requested)
            .select_related('team').order_by('scheduled_date', 'start_time', 'pk'))
        if len(schedules) != len(requested):
            raise CommandError('One or more requested schedules do not exist.')
        plans = []
        for schedule in schedules:
            conflicts = SchedulePanelist.objects.filter(schedule=schedule, panelist_id=F('schedule__team__adviser_id'))
            if not conflicts.exists():
                self.stdout.write(f'{schedule.pk}: no adviser/panel conflict; skipped.')
                continue
            if schedule.status != DefenseSchedule.STATUS_SCHEDULED:
                raise CommandError(f'{schedule.pk}: only open scheduled defenses can be repaired; completed records need separate review.')
            excluded = set(schedule.panel_assignments.values_list('panelist_id', flat=True))
            excluded.update([schedule.team.adviser_id, schedule.documenter_id])
            candidates = get_user_model().objects.filter(
                role__in=['faculty', 'admin'], is_active=True, is_panelist=True,
            ).exclude(pk__in=[pk for pk in excluded if pk is not None]).annotate(
                workload=Count('schedule_panel_assignments', filter=Q(schedule_panel_assignments__schedule__status='scheduled')),
            ).order_by('workload', 'username', 'pk')
            last_blocker = 'No other eligible panelist is available.'
            for person in candidates:
                if any(p['replacement_id'] == person.pk and _overlap(schedule, p['schedule']) for p in plans):
                    continue
                serializer = OperationSerializer(data={
                    'action': 'preview_update', 'anchor_id': schedule.pk,
                    'expected_revisions': {str(schedule.pk): schedule.revision},
                    'reason': 'Correct adviser conflict: an adviser cannot sit on their own advisee defense panel.',
                    'changes': {'panel_change': {'action': 'replace',
                        'panelist_id': schedule.team.adviser_id, 'replacement_id': person.pk}},
                })
                serializer.is_valid(raise_exception=True)
                try:
                    execute_operation(actor, serializer.validated_data)
                except APIException as exc:
                    last_blocker = str(exc.detail)
                    continue
                plan = {'schedule': schedule, 'replacement_id': person.pk, 'data': serializer.validated_data}
                plans.append(plan)
                self.stdout.write(f'{schedule.pk} / {schedule.team.name}: replace adviser with {person.get_full_name() or person.username} (faculty #{person.pk}).')
                break
            else:
                raise CommandError(f'{schedule.pk}: no safe replacement. {last_blocker}')
        if options['apply']:
            try:
                for plan in plans:
                    execute_operation(actor, {**plan['data'], 'action': 'update'})
            except APIException as exc:
                raise CommandError(f'Correction rejected; all changes rolled back: {exc.detail}') from exc
            self.stdout.write(self.style.SUCCESS(f'Corrected {len(plans)} schedules with audited panel changes.'))
        else:
            self.stdout.write(f'Preview only: {len(plans)} corrections; no records changed. Use --apply to save.')
