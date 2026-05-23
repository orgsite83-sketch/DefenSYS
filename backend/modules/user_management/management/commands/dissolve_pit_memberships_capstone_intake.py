"""One-time repair: clear PIT team memberships for Capstone 1 intake cohort."""

from django.core.management.base import BaseCommand
from django.db.models import Count

from academic_period_management.capstone_mode import derive_capstone_program_phase
from academic_period_management.models import Semester
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord
from user_management.academic_records.rollover import active_semester


class Command(BaseCommand):
    help = (
        'Remove PIT team memberships for students on the active semester who are '
        '3rd Year (Capstone 1 intake). Use after rollover before capstone bulk import.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report how many memberships would be cleared without deleting.',
        )

    def handle(self, *args, **options):
        active = active_semester()
        if active is None:
            self.stderr.write('No active semester is configured.')
            return

        if active.label != Semester.SECOND:
            self.stderr.write(
                f'Active semester is {active.label!r}; expected {Semester.SECOND!r}.',
            )
            return

        if derive_capstone_program_phase(active) != Semester.PHASE_CAPSTONE_1:
            self.stderr.write(
                'Active semester is not Capstone 1 intake (capstone_program_phase).',
            )
            return

        student_ids = list(
            StudentAcademicRecord.objects.filter(
                semester=active,
                year_level=StudentAcademicRecord.THIRD_YEAR,
            ).values_list('student_id', flat=True)
            .distinct()
        )
        if not student_ids:
            self.stdout.write('No 3rd Year records on the active semester.')
            return

        queryset = TeamMembership.objects.filter(
            student_id__in=student_ids,
            team__level__icontains='PIT',
        )
        count = queryset.count()
        if options['dry_run']:
            self.stdout.write(
                f'Dry run: would clear {count} PIT membership(s) '
                f'for {len(student_ids)} student(s).',
            )
            return

        cleared, _ = queryset.delete()
        emptied = (
            StudentTeam.objects.filter(level__icontains='PIT')
            .annotate(member_count=Count('memberships'))
            .filter(member_count=0)
            .count()
        )
        self.stdout.write(
            self.style.SUCCESS(
                f'Cleared {cleared} PIT membership(s); {emptied} PIT team(s) now have no members.',
            )
        )
