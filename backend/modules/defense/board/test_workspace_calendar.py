from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from dashboards import test_schedule_planner_history as planner_fixtures
from defense.scheduler.models import SchedulePanelist
from authentication_access_control.scopes import manageable_schedules_for
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
        self.assertEqual(self.rows('operations'), {lead_only.pk})
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

    def test_operations_do_not_inherit_other_year_panel_assignments(self):
        self.lead.pit_lead_year = '3rd Year'
        self.lead.is_panelist = True
        self.lead.save(update_fields=['pit_lead_year', 'is_panelist'])
        own = self.schedule(year='3rd Year', event_name='Third Year Hearing')
        other = self.schedule(year='2nd Year', event_name='Second Year Showcase')
        other.team.section = 'BSIT-2A'
        other.team.save(update_fields=['section'])
        SchedulePanelist.objects.create(schedule=other, panelist=self.lead)
        self.client.force_authenticate(self.lead)

        self.assertEqual(self.rows(), {own.pk, other.pk})
        for filters in ({}, {'scope': 'pit'}, {'search': 'Showcase'},
                        {'section': 'BSIT-2A'}, {'scope': 'capstone'}):
            with self.subTest(filters=filters):
                response = self.client.get('/api/defense/board/',
                                           {'workspace': 'operations', **filters})
                self.assertEqual(response.status_code, 200, response.data)
                self.assertNotIn(other.pk, {row['id'] for row in response.data['schedules']})
                self.assertEqual(response.data['counts']['all'], 1)
                self.assertEqual(response.data['stage_options'], ['Third Year Hearing'])
                self.assertEqual(response.data['sections'], [])
        self.assertEqual(self.rows('operations'), {own.pk})

        # Independent panel duties and shared calendar occupancy remain visible.
        panel = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(panel.status_code, 200, panel.data)
        self.assertIn(other.pk, {row['schedule_id'] for row in panel.data['teams']})
        calendar = self.client.get('/api/dashboards/schedule-planner/',
            {'start': self.day.isoformat(), 'end': self.day.isoformat()})
        self.assertEqual(calendar.status_code, 200, calendar.data)
        shared = next(row for row in calendar.data['sessions']
                      if row['session_id'] == str(other.session_id))
        self.assertFalse(shared['can_open'])

        board = self.client.get('/api/defense/board/').data['schedules']
        self.assertEqual({row['id']: row['can_manage'] for row in board},
                         {own.pk: True, other.pk: False})
        self.assertFalse(manageable_schedules_for(self.lead).filter(pk=other.pk).exists())
        self.assertEqual(self.client.get('/api/defense/board/operations/',
            {'history_for': other.pk}).status_code, 404)
        self.assertEqual(self.client.get('/api/defense/board/operations/',
            {'history_for': own.pk}).status_code, 200)
        self.assertEqual(self.client.patch(f'/api/defense/board/{other.pk}/',
            {'status': 'done'}, format='json').status_code, 404)
        self.assertEqual(self.client.delete(f'/api/defense/board/{other.pk}/').status_code, 404)
        denied = self.client.post('/api/defense/board/operations/', {
            'action': 'preview_update', 'anchor_id': other.pk,
            'changes': {'room': 'Other Room'},
        }, format='json')
        self.assertEqual(denied.status_code, 403, denied.data)
        other.refresh_from_db()
        self.assertEqual(other.room, 'Room 301')

    def test_operations_fail_closed_without_a_pit_year_despite_assignments(self):
        assigned = self.schedule()
        SchedulePanelist.objects.create(schedule=assigned, panelist=self.lead)
        self.lead.pit_lead_year = ''
        self.lead.save(update_fields=['pit_lead_year'])
        self.assertEqual(self.rows(), {assigned.pk})
        self.assertEqual(self.rows('operations'), set())

    def test_operations_include_all_schedules_for_admin_and_no_faculty_management(self):
        own = self.schedule()
        other = self.schedule(year='2nd Year')
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/defense/board/', {'workspace': 'operations'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({row['id'] for row in response.data['schedules']}, {own.pk, other.pk})
        self.assertTrue(all(row['can_manage'] for row in response.data['schedules']))
        SchedulePanelist.objects.create(schedule=other, panelist=self.lead)
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        self.assertEqual(self.rows(), {other.pk})
        self.assertEqual(self.rows('operations'), set())
