"""Export files must retain the import layouts, identities and authorized scope."""
import base64
import hashlib
import io
import os
from datetime import date, time
from pathlib import Path

import openpyxl
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from student_teams.models import SectionAssignment, StudentTeam, TeamMembership, TeamTermParticipation
from user_management.models import SectionInstructorAssignment

User = get_user_model()


class ImportTemplateExportTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='template-admin', role='admin', is_staff=True)
        cls.adviser = User.objects.create_user(username='template-adviser', role='faculty',
                                              first_name='Renato', last_name='Villanueva', is_adviser=True)
        cls.instructor = User.objects.create_user(username='template-instructor', role='faculty',
                                                 first_name='Ana', last_name='Peña')
        cls.documenter = User.objects.create_user(username='template-documenter', role='faculty',
                                                 first_name='Mia', last_name='Cruz', is_documenter=True)
        cls.year = SchoolYear.objects.create(label='2031-2032')
        cls.semester = Semester.objects.create(school_year=cls.year, label=Semester.FIRST, is_active=True)
        cls.stage = DefenseStage.objects.create(label='Concept Proposal', is_active=True, display_order=1)
        cls.students = [User.objects.create_user(username=f'export-student-{i}', role='student',
                       first_name=first, last_name=last) for i, (first, last) in enumerate([
                           ('Kenneth', 'DIZON'), ('Princess', 'LOPEZ'), ('Mark', 'VALENZUELA'), ('Camille', 'RAMOS')])]
        cls.team = StudentTeam.objects.create(name='Team EcoSort', project_title='AI-Powered Waste Sorting',
                   semester=cls.semester, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year',
                   section='BSIT-4B', leader=cls.students[0], adviser=cls.adviser)
        for order, student in enumerate(reversed(cls.students)):
            TeamMembership.objects.create(team=cls.team, student=student, is_leader=student == cls.students[0], order=order)
        cls.pit = StudentTeam.objects.create(name='Team PIT', project_title='Campus information system',
                  semester=cls.semester, level=StudentTeam.LEVEL_2_PIT, year_level='2nd Year',
                  section='BSIT-2A', leader=cls.students[1])
        TeamMembership.objects.create(team=cls.pit, student=cls.students[1], is_leader=True)
        SectionInstructorAssignment.objects.create(faculty=cls.instructor, semester=cls.semester,
                                                   year_level='2nd Year', section='BSIT-2A')
        cls.panels = [User.objects.create_user(username=f'template-panel-{i}', role='faculty',
                      first_name='Panel', last_name=f'Person {i}', is_panelist=True) for i in range(4)]
        cls.schedule = DefenseSchedule.objects.create(team=cls.team, semester=cls.semester,
                       defense_stage=cls.stage, scope='capstone', scheduled_date=date(2031, 11, 20),
                       start_time=time(11, 30), slot_duration=60, room='Room 301', documenter=cls.documenter)
        for order, panel in enumerate(cls.panels):
            SchedulePanelist.objects.create(schedule=cls.schedule, panelist=panel, order=order,
                                            is_chair=order == 2)
        cls.pit_schedule = DefenseSchedule.objects.create(team=cls.pit, semester=cls.semester,
                           event_name='PIT Capstone Defense', scope='pit', scheduled_date=date(2031, 11, 21),
                           start_time=time(8), slot_duration=30, room='Smart Room')
        SchedulePanelist.objects.create(schedule=cls.pit_schedule, panelist=cls.panels[0], is_chair=True)

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def export(self, endpoint, **params):
        response = self.client.get(f'/api/reports/{endpoint}/', {
            'semester_id': self.semester.pk, 'export_format': 'xlsx', **params})
        self.assertEqual(response.status_code, 200, getattr(response, 'data', None))
        return response, openpyxl.load_workbook(io.BytesIO(response.content))

    def fixture(self, name, response):
        if os.environ.get('DEFENSYS_EXPORT_TEMPLATE_FIXTURES') == '1':
            folder = Path(__file__).resolve().parents[3] / 'frontend/test/fixtures/import_template_exports'
            folder.mkdir(parents=True, exist_ok=True)
            (folder / name).write_bytes(response.content)

    def test_team_columns_continuous_members_and_leader_first(self):
        response, workbook = self.export('team-roster', scope='capstone')
        sheet = workbook.active
        self.assertEqual([cell.value for cell in sheet[1]],
                         ['Team Name', 'Capstone Project', 'Section', 'Adviser', 'Team Members'])
        self.assertEqual(sheet.max_row, 5)
        self.assertEqual(sheet['A2'].value, 'Team EcoSort')
        self.assertEqual(sheet['B2'].value, self.team.project_title)
        self.assertEqual(sheet['C2'].value, 'BSIT-4B')
        self.assertEqual(sheet['D2'].value, 'Renato Villanueva')
        self.assertEqual([sheet.cell(row, 5).value for row in range(2, 6)],
                         ['Kenneth DIZON', 'Camille RAMOS', 'Mark VALENZUELA', 'Princess LOPEZ'])
        self.assertIn('A2:A5', {str(area) for area in sheet.merged_cells.ranges})
        self.assertIsNone(sheet['B3'].value)
        self.assertFalse(sheet.protection.sheet)
        self.assertGreaterEqual(sheet.column_dimensions['B'].width, 55)
        self.fixture('capstone-teams.xlsx', response)

    def test_pit_instructor_and_shared_metadata_keep_their_import_columns(self):
        SectionAssignment.objects.create(semester=self.semester, section='BSIT-2A', year_level='2nd Year',
                                         system_name='Societree', project_manager=self.students[1])
        response, workbook = self.export('team-roster', scope='pit')
        sheet = workbook.active
        self.assertEqual(sheet['A1'].value, 'System Name:')
        self.assertEqual(sheet['B1'].value, 'Societree')
        self.assertEqual(sheet['B2'].value, 'Princess LOPEZ')
        self.assertEqual([cell.value for cell in sheet[4]],
                         ['Team Name', 'Module', 'Section', 'Instructor', 'Team Members'])
        self.assertEqual(sheet['D5'].value, 'Ana Peña')
        self.fixture('pit-shared-teams.xlsx', response)

    def test_blank_values_literal_titles_and_ambiguous_names(self):
        User.objects.create_user(username='different-kenneth', role='student', first_name='Kenneth', last_name='DIZON')
        self.team.project_title, self.team.adviser = '=literal title', None
        self.team.save(update_fields=['project_title', 'adviser'])
        _, workbook = self.export('team-roster', scope='capstone')
        sheet = workbook.active
        self.assertEqual(sheet['B2'].value, '=literal title')
        self.assertEqual(sheet['B2'].data_type, 's')
        self.assertIsNone(sheet['D2'].value)
        self.assertEqual(sheet['E2'].value, self.students[0].username)
        self.assertFalse(any(cell.data_type == 'f' for sheet in workbook for row in sheet for cell in row))

    def test_historical_roster_uses_frozen_members_title_and_adviser(self):
        TeamTermParticipation.objects.update_or_create(team=self.team, semester=self.semester, defaults={
            'project_version': 1, 'closed_at': timezone.now(), 'snapshot': {
                'name': 'Recorded Team', 'project_title': 'Recorded title', 'level': self.team.level,
                'year_level': '4th Year', 'section': 'BSIT-4A', 'leader_id': self.students[2].pk,
                'adviser_id': self.adviser.pk, 'adviser_name': 'Recorded adviser',
                'adviser_username': self.adviser.username, 'member_ids': [s.pk for s in self.students[2:]],
                'members': [{'student_id': s.pk, 'username': s.username, 'name': f'Recorded {i}'}
                            for i, s in enumerate(self.students[2:])],
            }})
        _, workbook = self.export('team-roster', scope='capstone')
        sheet = workbook.active
        self.assertEqual(sheet['A2'].value, 'Recorded Team')
        self.assertEqual(sheet['B2'].value, 'Recorded title')
        self.assertEqual(sheet['C2'].value, 'BSIT-4A')
        self.assertEqual(sheet['D2'].value, self.adviser.username)
        self.assertEqual(sheet.max_row, 3)
        self.assertEqual(sheet['E2'].value, self.students[2].username)

    def test_schedule_timetable_preserves_explicit_chair_order_and_documenter(self):
        response, workbook = self.export('defense-schedules', scope='capstone')
        sheet = workbook.active
        self.assertEqual(sheet['D3'].value, 'Stage: Concept Proposal')
        self.assertEqual(sheet['D4'].value.date(), date(2031, 11, 20))
        self.assertEqual(sheet['D5'].value, 'Room: Room 301')
        self.assertEqual([sheet.cell(6, col).value for col in range(4, 13)],
                         ['#', 'Time', 'Team Name', 'Adviser', 'Panel Chair', 'Panel Member 1',
                          'Panel Member 2', 'Panel Member 3', 'Documenter'])
        self.assertEqual(sheet['E7'].value, '11:30 AM - 12:30 PM')
        self.assertEqual(sheet['H7'].value, 'Panel Person 2')
        self.assertEqual([sheet.cell(7, col).value for col in (9, 10, 11)],
                         ['Panel Person 0', 'Panel Person 1', 'Panel Person 3'])
        self.assertEqual(sheet['L7'].value, 'Mia Cruz')
        self.fixture('capstone-schedules.xlsx', response)

    def test_pit_timetable_keeps_instructor_and_omits_capstone_documenter(self):
        response, workbook = self.export('defense-schedules', scope='pit')
        sheet = workbook.active
        self.assertEqual(sheet['G6'].value, 'Instructor')
        self.assertEqual(sheet['G7'].value, 'Ana Peña')
        self.assertEqual(sheet['E7'].value, '08:00 AM - 08:30 AM')
        self.assertEqual(sheet.max_column, 11)
        self.fixture('pit-schedules.xlsx', response)

    def test_multiple_days_and_rooms_stay_separate_and_staff_merges_are_local(self):
        for day, start, room in [(20, 13, 'Room 301'), (21, 8, 'Room 302')]:
            DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
                scope='capstone', scheduled_date=date(2031, 11, day), start_time=time(start),
                slot_duration=30, room=room, documenter=self.documenter)
        response, workbook = self.export('defense-schedules', scope='capstone')
        sheet = workbook.active
        self.assertIn('G7:G8', {str(area) for area in sheet.merged_cells.ranges})
        self.assertIn('L7:L8', {str(area) for area in sheet.merged_cells.ranges})
        self.assertEqual(sheet['D11'].value.date(), date(2031, 11, 21))
        self.assertEqual(sheet['D12'].value, 'Room: Room 302')
        self.fixture('multi-day-schedules.xlsx', response)

    def test_excel_preview_is_rendered_from_the_import_layout(self):
        from reports.workbook_preview import build_workbook_preview
        response, _ = self.export('team-roster', scope='capstone')
        preview = build_workbook_preview(response.content)
        self.assertEqual(preview['sha256'], hashlib.sha256(response.content).hexdigest())
        if os.environ.get('DEFENSYS_EXPORT_TEMPLATE_FIXTURES') == '1':
            folder = Path(__file__).resolve().parents[3] / '.tmp/import-template-export-previews'
            folder.mkdir(parents=True, exist_ok=True)
            for endpoint in ('team-roster', 'defense-schedules'):
                exported, _ = self.export(endpoint)
                for i, sheet in enumerate(build_workbook_preview(exported.content)['sheets']):
                    (folder / f'{endpoint}-{i}.pdf').write_bytes(base64.b64decode(sheet['pdf_base64']))

    def test_empty_and_restricted_exports_keep_headers_without_other_teams(self):
        lead = User.objects.create_user(username='export-pit-lead', role='faculty', is_pit_lead=True,
                                       pit_lead_year='1st Year')
        self.client.force_authenticate(lead)
        _, workbook = self.export('team-roster', scope='pit')
        self.assertEqual(workbook.active.max_row, 1)
        self.assertEqual(workbook.active['B1'].value, 'PIT Project')
        _, workbook = self.export('defense-schedules', scope='pit')
        self.assertEqual(workbook.active['G6'].value, 'Instructor')
        self.assertEqual(workbook.active.max_row, 6)

    def test_mixed_scope_export_keeps_all_teams_and_signatures_separate(self):
        import json
        response, workbook = self.export('team-roster', include_signatures='true', signatories=json.dumps([
            {'label': 'Verified by:', 'name': 'Report Reviewer', 'role': 'Coordinator'}]))
        self.assertEqual(workbook.sheetnames, ['Capstone Teams', 'PIT Teams', 'Signatories'])
        self.assertEqual(workbook['PIT Teams']['D2'].value, 'Ana Peña')
        self.assertNotIn('Report Reviewer', [cell.value for row in workbook.active for cell in row])
        self.fixture('mixed-teams.xlsx', response)
        response, workbook = self.export('defense-schedules', include_signatures='true')
        self.assertEqual(len(workbook.worksheets), 3)
        self.assertEqual(workbook.worksheets[-1].title, 'Signatories')
        self.fixture('mixed-schedules.xlsx', response)

    def test_export_does_not_drop_unrepresentable_panel_assignments(self):
        self.schedule.panel_assignments.update(is_chair=False)
        response = self.client.get('/api/reports/defense-schedules/', {
            'semester_id': self.semester.pk, 'scope': 'capstone', 'export_format': 'xlsx'})
        self.assertEqual(response.status_code, 400)
        self.assertIn('panel chair', str(response.data))
