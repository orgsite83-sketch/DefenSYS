"""
Remove dev-database rows created by the deliverable-upload debug probe.

Targets: school year 2027-2028, its semesters/teams, and users t-admin / t-stu.
Does not touch 2026-2027 or other real demo data.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from repository.vault.models import VaultEntry
from student_teams.models import StudentTeam, TeamMembership


PROBE_SCHOOL_YEAR = '2027-2028'
PROBE_USERNAMES = ('t-admin', 't-stu')


class Command(BaseCommand):
    help = 'Delete debug probe academic period, teams, and users from the dev database.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Print what would be deleted without changing the database.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        User = get_user_model()

        school_year = SchoolYear.objects.filter(label=PROBE_SCHOOL_YEAR).first()
        probe_users = list(User.objects.filter(username__in=PROBE_USERNAMES))

        if not school_year and not probe_users:
            self.stdout.write(self.style.WARNING('No debug probe data found.'))
            return

        teams = (
            StudentTeam.objects.filter(semester__school_year=school_year)
            if school_year
            else StudentTeam.objects.none()
        )
        semesters = (
            Semester.objects.filter(school_year=school_year)
            if school_year
            else Semester.objects.none()
        )

        self.stdout.write('Debug probe cleanup plan:')
        if school_year:
            self.stdout.write(f'  School year: {school_year.label} (id={school_year.id})')
        for semester in semesters:
            self.stdout.write(
                f'  Semester: {semester.label} (id={semester.id}, active={semester.is_active})'
            )
        for team in teams:
            self.stdout.write(
                f'  Team: {team.name} / {team.project_title} '
                f'(id={team.id}, level={team.level})'
            )
            self.stdout.write(
                f'    memberships={TeamMembership.objects.filter(team=team).count()}, '
                f'deliverables={DeliverableSubmission.objects.filter(team=team).count()}, '
                f'schedules={DefenseSchedule.objects.filter(team=team).count()}, '
                f'grades={TeamGrade.objects.filter(team=team).count()}, '
                f'vault={VaultEntry.objects.filter(team=team).count()}'
            )
        for user in probe_users:
            self.stdout.write(f'  User: {user.username} (id={user.id})')

        if dry_run:
            self.stdout.write(self.style.WARNING('Dry run only — no rows deleted.'))
            return

        with transaction.atomic():
            for team in teams:
                TeamGrade.objects.filter(team=team).delete()
                DeliverableSubmission.objects.filter(team=team).delete()
                DefenseSchedule.objects.filter(team=team).delete()
                VaultEntry.objects.filter(team=team).delete()
                team.delete()

            if school_year:
                semesters.delete()
                school_year.delete()

            deleted_users, _ = User.objects.filter(username__in=PROBE_USERNAMES).delete()

        self.stdout.write(self.style.SUCCESS('Debug probe data removed.'))
        if deleted_users:
            self.stdout.write(f'  Users deleted: {deleted_users}')
