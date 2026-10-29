"""Term-scoped instructor regression coverage."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from student_teams.models import StudentTeam
from user_management.models import SectionInstructorAssignment
from . import test_submission_timing as fixtures
from .services import resolve_team_instructor_or_adviser_name


class FeatureRegressionTests(APITestCase):
    setUp = fixtures.SubmissionTimingTests.setUp


    def test_instructor_lookup_uses_the_teams_semester(self):
        users = get_user_model().objects
        old = users.create_user(username='prior-instructor', role='faculty', last_name='Aardvark')
        current = users.create_user(username='current-instructor', role='faculty', last_name='Zebra')
        old_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.team.level = StudentTeam.LEVEL_3_PIT
        self.team.section = 'BSIT-3A'
        self.team.adviser = None
        self.team.save()
        for person, term in ((old, old_term), (current, self.semester)):
            SectionInstructorAssignment.objects.create(faculty=person, semester=term,
                year_level=self.team.year_level, section=self.team.section)
        self.assertEqual(resolve_team_instructor_or_adviser_name(self.team), 'Zebra')
