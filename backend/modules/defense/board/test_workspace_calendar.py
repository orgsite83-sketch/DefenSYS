from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from dashboards import test_schedule_planner_history as planner_fixtures
from defense.scheduler.models import SchedulePanelist
from user_management.models import SectionInstructorAssignment


class FacultyCalendarScopeTests(APITestCase):
    setUp = planner_fixtures.SchedulePlannerHistoryTests.setUp
    schedule = planner_fixtures.SchedulePlannerHistoryTests.schedule

    def rows(self, workspace=None):
        self.client.force_authenticate(self.lead)
        response = self.client.get('/api/defense/board/', {'workspace': workspace} if workspace else {})
        self.assertEqual(response.status_code, 200, response.data)
        return {item['id'] for item in response.data['schedules']}

    def test_calendar_scopes_do_not_inherit_other_faculty_duties(self):
        advised = self.schedule(scope='capstone', year='4th Year')
        advised.team.adviser = self.lead
        advised.team.save()
        taught = self.schedule(year='2nd Year')
        taught.team.section = 'BSIT-2A'
        taught.team.save()
        SectionInstructorAssignment.objects.create(
            faculty=self.lead, semester=self.semester, year_level='2nd Year', section='BSIT-2A',
        )
        panel_only = self.schedule(year='3rd Year')
        SchedulePanelist.objects.create(schedule=panel_only, panelist=self.lead)
        lead_only = self.schedule(year='1st Year')
        old_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        old = self.schedule(scope='capstone', year='4th Year', semester=old_term)
        old.team.adviser = self.lead
        old.team.save()

        self.assertEqual(self.rows('adviser'), {advised.pk})
        self.assertEqual(self.rows('instructor'), {taught.pk})
        self.assertIn(panel_only.pk, self.rows())
        self.assertIn(lead_only.pk, self.rows())

    def test_inactive_section_assignments_do_not_populate_instructor_calendar(self):
        taught = self.schedule()
        taught.team.section = 'BSIT-1A'
        taught.team.save()
        SectionInstructorAssignment.objects.create(
            faculty=self.lead, semester=self.semester, year_level='1st Year', section='BSIT-1A',
            is_active=False,
        )
        self.assertEqual(self.rows('instructor'), set())
