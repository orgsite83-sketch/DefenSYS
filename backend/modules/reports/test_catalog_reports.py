import io
from datetime import date, time
from pathlib import Path
from unittest.mock import patch

import openpyxl
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership
from grading.rubrics.models import Rubric, RubricCriterion
from defense.stages.models import DefenseStage, StageGradingConfig, StageDeliverable
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import ExternalEvaluator, GuestPanelistCode
from repository.archive.models import ArchiveEntry
from reports.catalog_reports import BUILDERS


class CatalogReportTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='export-admin', role='admin', first_name='Export', last_name='Administrator')
        cls.lead = User.objects.create_user(username='export-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        cls.student = User.objects.create_user(username='2026-export-student', role='student', first_name='Andrea', last_name='Santos')
        cls.year = SchoolYear.objects.create(label='2040-2041')
        cls.sem = Semester.objects.create(school_year=cls.year, label='1st Semester', is_active=True)
        cls.old_sem = Semester.objects.create(school_year=cls.year, label='2nd Semester')
        cls.stage, _ = DefenseStage.objects.get_or_create(label='Export Proposal', defaults={'display_order': 1})
        cls.team = StudentTeam.objects.create(name='Export Team', project_title='Patient Records System',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4A', semester=cls.sem, leader=cls.student)
        cls.pit_team = StudentTeam.objects.create(name='PIT Export Team', project_title='Smart Campus',
            level=StudentTeam.LEVEL_2_PIT, year_level='2nd Year', section='BSIT-2A', semester=cls.sem, leader=cls.student)
        cls.other_pit = StudentTeam.objects.create(name='Other Year Team', project_title='Other project',
            level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=cls.sem, leader=cls.student)
        TeamMembership.objects.create(team=cls.team, student=cls.student)
        cls.rubric = Rubric.objects.create(name='Proposal Quality Guide', scope='capstone', semester=cls.sem,
            defense_stage=cls.stage, evaluation_type='panel', status='published', created_by=cls.admin)
        cls.description = ('Design evidence <verified> & documented. ' * 140) + 'COMPLETE DESCRIPTION END'
        RubricCriterion.objects.create(rubric=cls.rubric, name='System Design', description=cls.description,
            scale=Rubric.SCALE_10, max_score=10, weight=100, display_order=1)
        StageGradingConfig.objects.create(defense_stage=cls.stage, semester=cls.sem, panel_rubric=cls.rubric,
            panel_weight=60, adviser_weight=25, peer_weight=15)
        StageDeliverable.objects.create(defense_stage=cls.stage, deliverable_id='D1', label='Proposal Paper', required=True)
        cls.pit_rubric = Rubric.objects.create(name='IT Olympics Scoring', scope='pit', semester=cls.sem,
            event_name='IT Olympics', evaluation_type='panel', status='published', created_by=cls.lead)
        PitEventGradingConfig.objects.create(semester=cls.sem, event_name='IT Olympics', panel_rubric=cls.pit_rubric,
            panel_weight=75, peer_weight=25)
        StudentAcademicRecord.objects.create(student=cls.student, semester=cls.sem, year_level='4th Year', section='BSIT-4A')
        cls.archive = ArchiveEntry.objects.create(entry_type='capstone', team=cls.team,
            file_name='Student Performance Analytics and Early Warning with Complete Filename.pdf',
            team_name=cls.team.name, year_level='4th Year', academic_year=cls.year.label,
            semester_label=cls.sem.label, stage_label=cls.stage.label, uploaded_by=cls.admin, uploaded_at=timezone.now())
        cls.schedule = DefenseSchedule.objects.create(team=cls.team, semester=cls.sem, defense_stage=cls.stage,
            scheduled_date=date(2040, 10, 15), start_time=time(9, 30), room='Room A', scope='capstone')
        cls.evaluator = ExternalEvaluator.objects.create(name='Dr. Maria Rivera', email='export@example.test', institution='Partner University', status='approved', created_by=cls.admin)
        cls.invitation = GuestPanelistCode.objects.create(code='SECRET-EXPORT', evaluator=cls.evaluator,
            guest_name=cls.evaluator.name, defense_schedule=cls.schedule, created_by=cls.admin)

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def report(self, path, params=None):
        return self.client.get(path, {'export_format': 'json', **(params or {})})

    def test_every_catalog_report_supports_preview_pdf_and_excel(self):
        for kind in BUILDERS:
            for format_value in ('json', 'pdf', 'xlsx'):
                with self.subTest(report=kind, format=format_value):
                    response = self.report(f'/api/reports/{kind}/', {'export_format': format_value})
                    self.assertEqual(response.status_code, 200, getattr(response, 'data', None))
                    if format_value == 'json':
                        self.assertTrue(response.data.get('pdf_base64'), f'{kind}: PDF preview failed')
                        self.assertIn('rows', response.data)
                    elif format_value == 'pdf':
                        self.assertTrue(response.content.startswith(b'%PDF'))
                    else:
                        workbook = openpyxl.load_workbook(io.BytesIO(response.content))
                        self.assertTrue(workbook.active.freeze_panes)
                        self.assertTrue(workbook.active.auto_filter.ref)

    def test_rubric_export_preserves_complete_criteria_and_effective_weights(self):
        response = self.report(f'/api/reports/rubrics/{self.rubric.pk}/', {'export_format': 'xlsx'})
        self.assertEqual(response.status_code, 200)
        workbook = openpyxl.load_workbook(io.BytesIO(response.content))
        self.assertIn('Criteria', workbook.sheetnames)
        main_text = str(list(workbook.active.values))
        self.assertIn('Panel: 60%', main_text)
        values = list(workbook['Criteria'].values)
        description = ''.join(str(row[2]) for row in values if row[0] == self.rubric.name)
        self.assertEqual(description, self.description)
        pdf = self.report(f'/api/reports/rubrics/{self.rubric.pk}/', {'export_format': 'pdf'})
        self.assertTrue(pdf.content.startswith(b'%PDF'))
        output = Path(__file__).resolve().parents[3] / '.tmp'
        output.mkdir(exist_ok=True)
        (output / 'rubric-export-qa.pdf').write_bytes(pdf.content)

    def test_project_register_filters_all_rows_and_uses_excel_dates(self):
        params = {'search': 'Student Performance', 'type': 'capstone', 'year_level': '4th Year', 'academic_year': self.year.label, 'export_format': 'xlsx', 'page_size': 1}
        response = self.report('/api/reports/project-records/', params)
        self.assertEqual(response.status_code, 200)
        worksheet = openpyxl.load_workbook(io.BytesIO(response.content)).active
        rows = [row for row in worksheet.iter_rows() if row[1].value == self.archive.file_name]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][-1].data_type, 'd')
        self.assertGreaterEqual(worksheet.column_dimensions['B'].width, 50)
        self.assertTrue(rows[0][1].alignment.wrap_text)

    def test_enrollment_local_filters_match_source_records(self):
        response = self.report('/api/reports/student-enrollment/', {'section': 'BSIT-4A', 'year_level': '4th Year'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([row['name'] for row in response.data['rows']], ['Andrea Santos'])
        empty = self.report('/api/reports/student-enrollment/', {'section': 'UNASSIGNED'})
        self.assertEqual(empty.data['rows'], [])
        self.assertTrue(empty.data['pdf_base64'])

    def test_readiness_does_not_mutate_schedules_or_teams(self):
        with patch.object(DefenseSchedule, 'save', side_effect=AssertionError('Export must not normalize schedules')), patch.object(StudentTeam, 'save', side_effect=AssertionError('Export must not modify teams')):
            response = self.report('/api/reports/readiness/', {'stage': self.stage.label, 'scope': 'capstone'})
            self.assertEqual(response.status_code, 200)
            self.assertEqual([row['team'] for row in response.data['rows']], [self.team.name])

    def test_pit_lead_cannot_widen_year_or_capstone_visibility(self):
        self.client.force_authenticate(self.lead)
        response = self.report('/api/reports/overview/', {'scope': 'capstone', 'year_level': '4th Year'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rows'][0]['value'], 0)
        options = self.report('/api/reports/catalog-options/')
        self.assertEqual(options.status_code, 200)
        self.assertEqual([row['id'] for row in options.data['teams']], [self.pit_team.pk])
        self.assertNotIn(self.rubric.pk, [row['id'] for row in options.data['rubrics']])
        denied = self.report('/api/reports/academic-periods/')
        self.assertEqual(denied.status_code, 403)
        rubric = self.report(f'/api/reports/rubrics/{self.rubric.pk}/')
        self.assertEqual(rubric.status_code, 404)

    def test_external_assignments_have_names_dates_and_no_credentials(self):
        response = self.report('/api/reports/external-evaluators/')
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(self.invitation.code, str(response.data))
        row = response.data['sections'][0]['rows'][0]
        self.assertEqual(row['date'], '2040-10-15')
        self.assertEqual(row['time'], '09:30')
        self.assertEqual(row['team'], self.team.name)

    def test_invalid_ids_and_missing_selections_are_controlled(self):
        for kind in BUILDERS:
            response = self.report(f'/api/reports/{kind}/', {'semester_id': 'broken'})
            self.assertEqual(response.status_code, 400)
        self.assertEqual(self.report('/api/reports/rubrics/999999/').status_code, 404)
        for kind in ('semester-grades', 'team-roster', 'defense-schedules'):
            self.assertEqual(self.report(f'/api/reports/{kind}/', {'semester_id': 'broken'}).status_code, 400)

    def test_source_roster_and_board_filters_are_applied(self):
        roster = self.report('/api/reports/team-roster/', {'search': 'Patient', 'section': 'BSIT-4A'})
        self.assertEqual([row['team_name'] for row in roster.data['rows']], [self.team.name])
        schedule = self.report('/api/reports/defense-schedules/', {'source_context': 'defense-board', 'section': 'BSIT-2A'})
        self.assertEqual(schedule.data['rows'], [])

    def test_nonmanager_cannot_export_private_registries(self):
        self.client.force_authenticate(self.student)
        for kind in ('academic-periods', 'faculty-directory', 'student-enrollment', 'project-records', 'external-evaluators', 'readiness', 'overview', 'curriculum-summary'):
            self.assertEqual(self.report(f'/api/reports/{kind}/').status_code, 403)
        self.client.force_authenticate(None)
        self.assertEqual(self.report('/api/reports/rubrics/').status_code, 401)

    def test_assignment_tab_exports_only_matching_defenses(self):
        response = self.report('/api/reports/external-evaluators/', {'view': 'assignments', 'search': 'Maria'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rows'][0]['team'], self.team.name)
        self.assertNotIn(self.invitation.code, str(response.data))
        empty = self.report('/api/reports/external-evaluators/', {'view': 'assignments', 'search': 'unmatched'})
        self.assertEqual(empty.data['rows'], [])

    def test_rubric_catalog_history_and_pit_weights(self):
        response = self.report('/api/reports/rubrics/', {'scope': 'pit'})
        self.assertEqual(response.data['rows'][0]['weights'], 'Panel: 75%, Peer: 25%')
        history = self.report('/api/reports/rubrics/', {'term_context': 'history'})
        self.assertEqual(history.data['rows'], [])

    def test_all_history_roster_export_retains_period_coverage(self):
        historical = StudentTeam.objects.create(name='Historical Export Team', project_title='Old Project',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', semester=self.old_sem, leader=self.student)
        response = self.report('/api/reports/team-roster/', {'term_context': 'all', 'search': 'Historical'})
        self.assertEqual([row['team_name'] for row in response.data['rows']], [historical.name])
