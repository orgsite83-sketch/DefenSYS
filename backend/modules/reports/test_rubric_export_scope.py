"""Workspace selection must agree across rubric previews, PDF and Excel."""
import io
from unittest.mock import patch

import openpyxl
import pdfplumber
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.rubrics.models import Rubric, RubricCriterion


class RubricExportScopeTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        users = get_user_model()
        cls.admin = users.objects.create_user(username='rubric-scope-admin', role='admin')
        cls.lead = users.objects.create_user(username='rubric-scope-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='2nd Year')
        year = SchoolYear.objects.create(label='2048-2049')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.old = Semester.objects.create(school_year=year, label=Semester.SECOND)
        cls.first = DefenseStage.objects.create(label='Export scope proposal', display_order=1,
            setup_semester=cls.semester)
        cls.second = DefenseStage.objects.create(label='Export scope final', display_order=2,
            setup_semester=cls.semester)
        cls.empty = DefenseStage.objects.create(label='Export scope unconfigured', display_order=3,
            setup_semester=cls.semester)
        cls.panel = cls.make_rubric('Proposal panel', 'panel', stage=cls.first)
        cls.peer = cls.make_rubric('Final peer', 'peer', stage=cls.second)
        # A past rubric reused in this term must follow its actual assignment,
        # even though its original stage and semester are different.
        cls.reused = cls.make_rubric('Reused final panel', 'panel', stage=cls.first, semester=cls.old)
        cls.orphan = cls.make_rubric('AAA obsolete final panel', 'panel', stage=cls.second)
        StageGradingConfig.objects.create(semester=cls.semester, defense_stage=cls.first, panel_rubric=cls.panel)
        StageGradingConfig.objects.create(semester=cls.semester, defense_stage=cls.second,
            panel_rubric=cls.reused, peer_rubric=cls.peer)
        StageGradingConfig.objects.create(semester=cls.old, defense_stage=cls.first, panel_rubric=cls.reused)
        cls.pit_panel = cls.make_rubric('Second year event panel', 'panel', scope='pit', creator=cls.lead)
        cls.pit_peer = cls.make_rubric('Second year event peer', 'peer', scope='pit', creator=cls.lead)
        cls.event = PitEventGradingConfig.objects.create(semester=cls.semester, event_name='Shared event name',
            year_level='2nd Year', panel_rubric=cls.pit_panel, peer_rubric=cls.pit_peer)
        cls.other_event = PitEventGradingConfig.objects.create(semester=cls.semester,
            event_name='Other year event', year_level='1st Year', panel_rubric=cls.pit_panel)
        PitEventGradingConfig.objects.create(semester=cls.old, event_name='Shared event name',
            year_level='2nd Year', panel_rubric=cls.pit_panel)

    @classmethod
    def make_rubric(cls, name, role, *, stage=None, semester=None, scope='capstone', creator=None):
        rubric = Rubric.objects.create(name=name, scope=scope, semester=semester or cls.semester,
            defense_stage=stage, evaluation_type=role, status='published', created_by=creator or cls.admin)
        RubricCriterion.objects.create(rubric=rubric, name=f'{name} criterion', weight=100, max_score=10)
        return rubric

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def report(self, **params):
        return self.client.get('/api/reports/rubrics/', {
            'assignment_scope': 'configured', 'scope': 'capstone',
            'semester_id': self.semester.pk, 'export_format': 'json', **params,
        })

    def test_selected_stage_and_evaluator_use_assignment_instead_of_first_catalog_rubric(self):
        response = self.report(stage_id=self.second.pk, evaluation_type='panel', term_context='active')
        self.assertEqual(response.status_code, 200)
        self.assertEqual([row['name'] for row in response.data['rows']], [self.reused.name])
        row = response.data['rows'][0]
        self.assertEqual(row['stage'], self.second.label)
        self.assertIn(self.semester.display_name, row['assigned_to'])
        self.assertNotIn(self.first.label, row['assigned_to'])
        self.assertNotIn(self.old.display_name, row['assigned_to'])

    def test_all_stages_and_evaluator_filters_exclude_templates_and_old_assignments(self):
        for role, expected in (
            ('', {self.panel.name, self.reused.name, self.peer.name}),
            ('panel', {self.panel.name, self.reused.name}),
            ('peer', {self.peer.name}),
            ('adviser', set()),
        ):
            with self.subTest(role=role):
                response = self.report(evaluation_type=role)
                self.assertEqual(response.status_code, 200)
                self.assertEqual({row['name'] for row in response.data['rows']}, expected)

    def test_unconfigured_stage_does_not_fall_back_to_another_stage(self):
        response = self.report(stage_id=self.empty.pk, evaluation_type='panel')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rows'], [])
        self.assertTrue(response.data['pdf_base64'])

    def test_pdf_and_excel_retain_the_same_stage_and_role_as_preview(self):
        params = {'stage_id': self.second.pk, 'evaluation_type': 'panel'}
        pdf = self.report(**params, export_format='pdf')
        self.assertEqual(pdf.status_code, 200)
        with pdfplumber.open(io.BytesIO(pdf.content)) as document:
            text = '\n'.join(page.extract_text() or '' for page in document.pages)
        self.assertIn(self.reused.name, text)
        self.assertIn(self.second.label, text)
        self.assertNotIn(self.first.label, text)
        self.assertNotIn(self.orphan.name, text)
        self.assertNotIn(self.peer.name, text)
        excel = self.report(**params, export_format='xlsx')
        self.assertEqual(excel.status_code, 200)
        workbook = openpyxl.load_workbook(io.BytesIO(excel.content))
        text = str([list(sheet.values) for sheet in workbook])
        self.assertIn(self.reused.name, text)
        self.assertIn(self.second.label, text)
        self.assertNotIn(self.first.label, text)
        self.assertNotIn(self.orphan.name, text)
        self.assertNotIn(self.peer.name, text)

    def test_pit_event_selection_and_lead_year_are_enforced_by_id(self):
        self.client.force_authenticate(self.lead)
        response = self.report(scope='pit', pit_event_config_id=self.event.pk, evaluation_type='peer')
        self.assertEqual(response.status_code, 200)
        self.assertEqual([row['name'] for row in response.data['rows']], [self.pit_peer.name])
        denied = self.report(scope='pit', pit_event_config_id=self.other_event.pk)
        self.assertEqual(denied.status_code, 404)
        response = self.report(scope='pit')
        self.assertEqual({row['name'] for row in response.data['rows']}, {self.pit_panel.name, self.pit_peer.name})
        for row in response.data['rows']:
            self.assertEqual(row['assigned_to'].count('Shared event name'), 1)

    def test_wrong_period_and_conflicting_destination_never_widen_the_export(self):
        for params, status in (
            ({'stage_id': self.second.pk, 'semester_id': self.old.pk}, 404),
            ({'stage_id': self.second.pk, 'pit_event_config_id': self.event.pk}, 400),
            ({'scope': 'all'}, 400),
            ({'evaluation_type': 'unknown'}, 400),
        ):
            with self.subTest(params=params):
                self.assertEqual(self.report(**params).status_code, status)

    def test_workspace_preview_is_read_only(self):
        count = StageGradingConfig.objects.count()
        with patch('defense.stages.grading_config.get_or_create_stage_grading_config',
                   side_effect=AssertionError('Export must not create configuration')):
            self.assertEqual(self.report().status_code, 200)
        self.assertEqual(StageGradingConfig.objects.count(), count)
