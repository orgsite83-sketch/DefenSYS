"""
Re-sync grade rows and drop stale Unscheduled placeholders.

Safe to run on dev DB after endorsing a team without a defense schedule
(when Grade Center showed both Concept Proposal and Unscheduled).
"""

from django.core.management.base import BaseCommand
from django.db.models import Count

from grading.grades.models import TeamGrade
from grading.grades.services import sync_missing_grade_rows


class Command(BaseCommand):
    help = (
        'Re-run grade sync and remove stale Unscheduled TeamGrade rows '
        'for the same team when stage context has advanced.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report duplicate groups only; do not sync or delete.',
        )

    def handle(self, *args, **options):
        duplicates = (
            TeamGrade.objects.values('team_id', 'semester_id', 'scope')
            .annotate(row_count=Count('id'))
            .filter(row_count__gt=1)
        )
        dup_count = duplicates.count()
        unscheduled_before = TeamGrade.objects.filter(stage_label='Unscheduled').count()

        if options['dry_run']:
            self.stdout.write(
                f'Dry run: {dup_count} team/semester/scope group(s) with multiple grades; '
                f'{unscheduled_before} Unscheduled row(s).'
            )
            return

        result = sync_missing_grade_rows()
        unscheduled_after = TeamGrade.objects.filter(stage_label='Unscheduled').count()
        duplicates_after = (
            TeamGrade.objects.values('team_id', 'semester_id', 'scope')
            .annotate(row_count=Count('id'))
            .filter(row_count__gt=1)
            .count()
        )

        self.stdout.write(self.style.SUCCESS('Grade sync complete.'))
        self.stdout.write(f'  sync result: {result}')
        self.stdout.write(f'  Unscheduled rows: {unscheduled_before} -> {unscheduled_after}')
        self.stdout.write(f'  Duplicate groups remaining: {duplicates_after}')
