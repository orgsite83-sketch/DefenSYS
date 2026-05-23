"""Remove all admin-configured stage deliverables (opt-in cleanup)."""

from django.core.management.base import BaseCommand
from django.db import transaction

from defense.stages.models import StageDeliverable


class Command(BaseCommand):
    help = 'Delete all StageDeliverable rows. Stages stay; deliverable checklists must be reconfigured in Defense Stages.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Print how many rows would be deleted without deleting.',
        )

    def handle(self, *args, **options):
        count = StageDeliverable.objects.count()
        if options['dry_run']:
            self.stdout.write(f'Would delete {count} StageDeliverable row(s).')
            return

        with transaction.atomic():
            deleted, _ = StageDeliverable.objects.all().delete()

        self.stdout.write(self.style.SUCCESS(f'Deleted {deleted} StageDeliverable row(s).'))
