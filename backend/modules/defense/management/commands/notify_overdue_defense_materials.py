from django.core.management.base import BaseCommand
from defense.scheduler.materials import sync_overdue_notifications


class Command(BaseCommand):
    help = 'Send one in-app reminder per overdue defense-material deadline. Safe to run every minute.'

    def handle(self, *args, **options):
        count = sync_overdue_notifications()
        self.stdout.write(f'Notified {count} defenses with overdue materials.')
