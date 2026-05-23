"""
DEV ONLY — remove ad-hoc test accounts that were never part of CSV imports.

Targets short usernames like a1, f1, s1, s2 created during local debugging or experiments.
Does NOT delete demo CSV students (4081–4084) or your bootstrap admin unless listed below.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from user_management.academic_records.models import StudentAcademicRecord


User = get_user_model()

# Add usernames here only for known throwaway accounts — not production users.
LEFTOVER_DEV_USERNAMES = [
    'a1',
    'f1',
    's1',
    's2',
]


class Command(BaseCommand):
    help = 'DEV ONLY: Delete leftover debug/test user accounts (a1, f1, s1, s2, etc.)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='List accounts that would be deleted without deleting them.',
        )
        parser.add_argument(
            '--username',
            action='append',
            dest='extra_usernames',
            help='Additional username to delete (repeatable).',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        usernames = list(LEFTOVER_DEV_USERNAMES) + list(options.get('extra_usernames') or [])

        self.stdout.write(self.style.WARNING('DEV ONLY — not for production without review'))
        deleted = 0
        not_found = 0

        for username in dict.fromkeys(usernames):
            user = User.objects.filter(username=username).first()
            if user is None:
                not_found += 1
                self.stdout.write(f'  not found: {username}')
                continue

            display = f'{user.first_name} {user.last_name}'.strip() or username
            if dry_run:
                self.stdout.write(f'  would delete: {username} ({display}, role={user.role})')
                deleted += 1
                continue

            StudentAcademicRecord.objects.filter(student=user).delete()
            user.delete()
            deleted += 1
            self.stdout.write(self.style.SUCCESS(f'  deleted: {username} ({display})'))

        summary = f'Done. deleted={deleted}, not_found={not_found}'
        if dry_run:
            summary = f'Dry run. would_delete={deleted}, not_found={not_found}'
        self.stdout.write(self.style.SUCCESS(summary))
