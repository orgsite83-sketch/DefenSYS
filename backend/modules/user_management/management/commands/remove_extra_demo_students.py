from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db.utils import ProgrammingError

from user_management.academic_records.models import StudentAcademicRecord


User = get_user_model()

EXTRA_DEMO_STUDENT_USERNAMES = [
    '4085',
    '4086',
    '4087',
    '4088',
    '4089',
    '4090',
    '4091',
    '4092',
]


class Command(BaseCommand):
    help = 'Remove extra 3rd-year demo students (4085-4092); keep 4081-4084 for single-team demo.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='List accounts that would be deleted without deleting them.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        deleted = 0
        not_found = 0
        skipped = 0

        for username in EXTRA_DEMO_STUDENT_USERNAMES:
            user = User.objects.filter(username=username, role='student').first()
            if user is None:
                not_found += 1
                self.stdout.write(f'  not found: {username}')
                continue

            display = f'{user.first_name} {user.last_name}'.strip() or username
            if dry_run:
                self.stdout.write(f'  would delete: {username} ({display})')
                deleted += 1
                continue

            self._delete_student_user(user)
            deleted += 1
            self.stdout.write(self.style.SUCCESS(f'  deleted: {username} ({display})'))

        summary = f'Done. deleted={deleted}, not_found={not_found}, skipped={skipped}'
        if dry_run:
            summary = f'Dry run. would_delete={deleted}, not_found={not_found}'
        self.stdout.write(self.style.SUCCESS(summary))

    def _delete_student_user(self, user):
        """Remove student-owned rows, then delete the user row (skips broken legacy FK collectors)."""
        from student_teams.models import TeamMembership

        StudentAcademicRecord.objects.filter(student_id=user.id).delete()
        TeamMembership.objects.filter(student_id=user.id).delete()

        try:
            from student_teams.weekly_progress.models import WeeklyProgressReport

            WeeklyProgressReport.objects.filter(student_id=user.id).delete()
        except Exception:
            pass

        User.objects.filter(pk=user.pk).update(team_id=None)

        queryset = User.objects.filter(pk=user.pk, role='student')
        deleted_count = queryset._raw_delete(queryset.db)
        if deleted_count == 0:
            raise ProgrammingError(f'Could not delete user pk={user.pk}')
