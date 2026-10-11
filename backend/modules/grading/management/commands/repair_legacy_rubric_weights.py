"""Convert legacy equal unit weights to exact percentages without replacing criteria."""

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from grading.rubrics.models import Rubric


class Command(BaseCommand):
    help = (
        'Preview legacy rubrics whose criteria all have weight 1.00. '
        'Use --apply to convert them to equal percentages, preserving IDs and scores. '
        'Only exact two-decimal equal allocations are repaired automatically.'
    )

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true', help='Apply and audit the repair.')
        parser.add_argument('--rubric-id', type=int, action='append', help='Limit to these rubric IDs.')

    @transaction.atomic
    def handle(self, *args, **options):
        rubrics = Rubric.objects.order_by('id')
        if options['rubric_id']:
            rubrics = rubrics.filter(pk__in=options['rubric_id'])
        if options['apply']:
            rubrics = rubrics.select_for_update()
        repaired = 0
        for rubric in rubrics:
            criteria_query = rubric.criteria.order_by('display_order', 'id')
            if options['apply']:
                criteria_query = criteria_query.select_for_update()
            criteria = list(criteria_query)
            if not criteria or any(item.weight != Decimal('1') for item in criteria):
                continue
            total = sum((item.weight for item in criteria), Decimal('0'))
            if total == 100:
                continue
            # Do not round unequal fractions or infer a custom allocation.
            if 10000 % len(criteria):
                self.stdout.write(f'Skipped rubric {rubric.pk}: exact equal percentages need more than two decimals.')
                continue
            weight = Decimal(10000 // len(criteria)) / Decimal(100)
            old_values = {'criteria': [{'id': item.pk, 'name': item.name, 'weight': str(item.weight)} for item in criteria]}
            if options['apply']:
                rubric.criteria.filter(pk__in=[item.pk for item in criteria]).update(
                    weight=weight, updated_at=timezone.now(),
                )
                log_high_impact_action(
                    category=SystemAuditLog.CATEGORY_RUBRICS,
                    action='rubric.weights_repair', target=rubric,
                    old_values=old_values,
                    new_values={'criteria': [{'id': item.pk, 'name': item.name, 'weight': f'{weight:.2f}'} for item in criteria]},
                    reason='Convert legacy equal unit weights to equivalent percentages; criterion IDs and recorded scores are preserved.',
                    strict=True,
                )
            repaired += 1
            self.stdout.write(f'Rubric {rubric.pk} ({rubric.name}): {total:.2f}% -> 100.00% ({weight:.2f}% each)')
        mode = 'Repaired' if options['apply'] else 'Dry run: would repair'
        self.stdout.write(f'{mode} {repaired} rubric(s).')
