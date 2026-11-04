"""Batch filters preserve intake identity and the existing adviser boundary."""
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from student_teams.models import StudentTeam
from student_teams.capstone_lifecycle import capture_participation
from .test_submission_timing import faculty_review_setup


class CapstoneBatchTests(APITestCase):
    setUp = faculty_review_setup

    def make_team(self, name, *, semester=None, intake=None, adviser=True):
        return StudentTeam.objects.create(name=name, project_title=name,
            semester=semester or self.semester, intake_semester=intake,
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year',
            leader=self.student, adviser=self.adviser if adviser else None)

    def get_list(self, **params):
        self.client.force_authenticate(self.adviser)
        return self.client.get(reverse('capstone_deliverables'), {
            'scope': 'capstone', 'workspace': 'adviser', **params})

    def close(self, team, outcome):
        row = capture_participation(team)
        row.outcome = outcome
        row.closed_at = timezone.now()
        row.save()

    def test_completed_and_failed_are_separate_from_ongoing(self):
        completed = self.make_team('Completed')
        failed = self.make_team('Failed')
        self.close(completed, 'completed')
        self.close(failed, 'failed')
        for status, expected in [('ongoing', {self.team.pk}),
                ('completed', {completed.pk}), ('failed', {failed.pk}),
                ('all', {self.team.pk, completed.pk, failed.pk})]:
            response = self.get_list(participation=status)
            self.assertEqual(response.status_code, 200)
            self.assertEqual({t['id'] for t in response.data['teams']}, expected)

    def test_continuation_stays_with_intake_and_options_ignore_search(self):
        intake = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        continuing = self.make_team('Continuing', intake=intake)
        new = self.make_team('Fresh intake', semester=intake, intake=intake)
        response = self.get_list(batch_id=str(intake.pk), participation='all')
        self.assertEqual(response.status_code, 200)
        self.assertEqual({t['id'] for t in response.data['teams']}, {continuing.pk, new.pk})
        response = self.get_list(search='no matching team', participation='completed')
        self.assertEqual(response.data['teams'], [])
        self.assertIn(str(intake.pk), {b['value'] for b in response.data['batch_options']})

    def test_foreign_batch_cannot_expand_adviser_access(self):
        other_intake = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.make_team('Someone else', semester=other_intake, intake=other_intake, adviser=False)
        response = self.get_list(batch_id=str(other_intake.pk), participation='all')
        self.assertEqual(response.data['teams'], [])
        self.assertNotIn(str(other_intake.pk), {b['value'] for b in response.data['batch_options']})

    def test_unresolved_intake_remains_visible_and_invalid_filters_fail(self):
        response = self.get_list(batch_id='unassigned', participation='ongoing')
        self.assertEqual({t['id'] for t in response.data['teams']}, {self.team.pk})
        for params in ({'batch_id': 'bad'}, {'participation': 'bad'}):
            self.assertEqual(self.get_list(**params).status_code, 400)
