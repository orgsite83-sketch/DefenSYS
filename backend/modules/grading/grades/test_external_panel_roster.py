"""Assigned external evaluators participate before and after their submission."""
from datetime import timedelta
from decimal import Decimal
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch

from django.conf import settings
from django.utils import timezone
from rest_framework.test import APITestCase

from user_management.models import ExternalEvaluator, GuestPanelistCode
from . import tests as fixtures
from .models import TeamGrade
from .serializers import TeamGradeSerializer
from .services import GradeContextService, submit_panelist_grade, team_grading_readiness

sys.path.insert(0, str(Path(settings.BASE_DIR).parent))
from execution import auto_panelist_eval as automation


class ExternalPanelRosterTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric

    def setUp(self):
        fixtures.GradeCenterApiTests.setUp(self)
        self.grade = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)[0]
        self.evaluator = ExternalEvaluator.objects.create(name='External Expert', status='approved')
        self.invitation = GuestPanelistCode.objects.create(
            evaluator=self.evaluator, guest_name=self.evaluator.name,
            defense_schedule=self.capstone_schedule, expires_at=timezone.now() + timedelta(days=1))
        self.invitation.schedules.add(self.capstone_schedule)
        self.key = f'guest:{self.invitation.pk}'

    def serialized(self):
        return TeamGradeSerializer(TeamGrade.objects.with_relations().get(pk=self.grade.pk)).data

    def submit_guest(self, score=10):
        return submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': score}],
            guest=SimpleNamespace(guest_code_id=self.invitation.pk, guest_name=self.invitation.guest_name,
                                  guest_code=self.invitation.code, token={'access_version': 1}))

    def test_pending_external_is_visible_once_and_required_before_submission(self):
        data = self.serialized()
        guests = [p for p in data['panelists'] if p.get('is_external')]
        self.assertEqual(guests, [{'id': None, 'username': self.key, 'name': self.evaluator.name,
                                   'panelist_key': self.key, 'is_external': True}])
        self.assertNotIn(self.invitation.code, str(data['panelists']))
        self.assertEqual(data['panel_evaluators_required'], 2)
        self.assertEqual(data['panel_evaluators_submitted'], 0)
        self.assertFalse(data['grading_ready'])

    def test_legacy_single_schedule_invitation_is_visible_and_discovered(self):
        self.invitation.schedules.clear()
        self.assertIn(self.key, [p.get('panelist_key') for p in self.serialized()['panelists']])
        invitations = automation.fetch_external_panelists([self.capstone_schedule.pk])
        self.assertEqual([i['id'] for i in invitations], [self.invitation.pk])

    def test_expired_invitation_stays_in_roster_and_reports_renewal_in_automation(self):
        self.invitation.expires_at = timezone.now() - timedelta(seconds=1)
        self.invitation.save(update_fields=['expires_at'])
        self.assertIn(self.key, [p.get('panelist_key') for p in self.serialized()['panelists']])
        invitations = automation.fetch_external_panelists([self.capstone_schedule.pk])
        self.assertIn('expired', invitations[0]['unavailable_reason'])
        self.assertIsNone(automation.get_guest_jwt_token(self.invitation.pk))

    def test_external_submission_contributes_to_mean_and_completion(self):
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 8}], panelist=self.panelist)
        self.grade.refresh_from_db()
        self.assertFalse(team_grading_readiness(self.grade, self.semester, 'capstone')['panel_complete'])
        self.submit_guest()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, Decimal('90'))
        data = self.serialized()
        self.assertEqual(data['panel_evaluators_required'], 2)
        self.assertEqual(data['panel_evaluators_submitted'], 2)
        scores = {row['panelist_key']: Decimal(row['percentage']) for row in data['panel_evaluation_scores']}
        self.assertEqual(scores, {self.panelist.username: Decimal('80'), self.key: Decimal('100')})

    def test_access_renewal_and_name_change_preserve_one_recorded_score_identity(self):
        self.submit_guest()
        original_code = self.invitation.code
        self.invitation.code = GuestPanelistCode.generate_unique_code()
        self.invitation.access_version += 1
        self.invitation.save(update_fields=['code', 'access_version'])
        self.evaluator.name = 'Renamed External Expert'
        self.evaluator.save(update_fields=['name'])
        data = self.serialized()
        self.assertEqual([p['name'] for p in data['panelists'] if p.get('is_external')], [self.evaluator.name])
        self.assertEqual([row['panelist_key'] for row in data['panel_evaluation_scores']], [self.key])
        self.assertNotIn(original_code, str(data))
        self.assertNotIn(self.invitation.code, str(data))

    def test_revocation_hides_unsubmitted_identity_but_preserves_recorded_scores(self):
        self.invitation.is_active = False
        self.invitation.save(update_fields=['is_active'])
        self.assertFalse(any(p.get('is_external') for p in self.serialized()['panelists']))
        self.invitation.is_active = True
        self.invitation.save(update_fields=['is_active'])
        self.submit_guest()
        self.invitation.is_active = False
        self.invitation.save(update_fields=['is_active'])
        self.assertTrue(any(p.get('panelist_key') == self.key for p in self.serialized()['panelists']))

    def test_roster_and_score_serialization_reuse_prefetched_relations(self):
        self.submit_guest()
        grade = TeamGrade.objects.with_relations().get(pk=self.grade.pk)
        serializer = TeamGradeSerializer()
        with self.assertNumQueries(0):
            serializer.get_panelists(grade)
            serializer.get_panel_evaluation_scores(grade)

    def test_grade_endpoints_never_expose_guest_access_codes(self):
        self.submit_guest()
        for url in [f'/api/grading/grades/{self.grade.pk}/', '/api/grading/grades/',
                    f'/api/grading/grades/{self.grade.pk}/corrections/']:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200, response.data)
            self.assertNotIn(self.invitation.code, str(response.data))
        for row in self.serialized()['breakdowns']:
            self.assertEqual(row['panelist_key'], self.key)
            self.assertEqual(row['evaluator_name'], self.evaluator.name)
            self.assertNotIn('Guest panelist:', row['remarks'])

    def test_older_table_clients_match_guest_username_to_recorded_scores(self):
        self.submit_guest()
        data = self.serialized()
        guest = next(p for p in data['panelists'] if p.get('is_external'))
        self.assertTrue(guest['username'])
        self.assertEqual([s['percentage'] for s in data['panel_evaluation_scores']
                          if s['panelist_key'] == guest['username']], ['100.00'])
        self.assertFalse(any('Guest panelist:' in row['remarks'] for row in data['breakdowns']))

    def test_missing_source_link_uses_saved_identity_and_removes_legacy_custom_code(self):
        self.submit_guest()
        self.grade.breakdowns.update(source_submission=None)
        data = self.serialized()
        self.assertEqual([s['panelist_key'] for s in data['panel_evaluation_scores']], [self.key])
        self.assertNotIn(self.invitation.code, str(data))
        from .models import GradeBreakdown
        from .serializers import GradeBreakdownSerializer
        orphan = GradeBreakdown(team_grade=self.grade, evaluation_type='panel', criterion_name='Legacy',
            score=Decimal('8'), max_score=Decimal('10'), remarks='Guest panelist: Other Expert (SECRET-CUSTOM)\nUseful feedback')
        public = GradeBreakdownSerializer(orphan).data
        self.assertEqual(public['evaluator_name'], 'Other Expert')
        self.assertEqual(public['remarks'], 'Useful feedback')
        self.assertNotIn('SECRET-CUSTOM', str(public))

    def test_both_target_scores_include_shared_and_individual_rows_without_secret_labels(self):
        from grading.rubrics.models import RubricCriterion
        self.panel_rubric.target_type = 'both'
        self.panel_rubric.save(update_fields=['target_type'])
        team_criterion = self.panel_rubric.criteria.first()
        individual = RubricCriterion.objects.create(rubric=self.panel_rubric, name='Individual Work',
            target_type='individual', max_score=10, weight=1, display_order=1)
        guest = SimpleNamespace(guest_code_id=self.invitation.pk, guest_name=self.invitation.guest_name,
            guest_code=self.invitation.code, token={'access_version': 1})
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': team_criterion.pk, 'score': 8}], guest=guest)
        for student, score in [(self.student, 10), (self.second_student, 6)]:
            submit_panelist_grade(self.capstone_schedule, self.grade,
                [{'criterion_id': individual.pk, 'score': score}], guest=guest, student=student)
        data = self.serialized()
        scores = {r['student_id']: r['percentage'] for r in data['panel_evaluation_scores']}
        self.assertEqual(scores, {self.student.pk: '90.00', self.second_student.pk: '70.00'})
        self.assertNotIn(self.invitation.code, str(data))

    def test_unlabelled_legacy_panel_scores_are_preserved(self):
        from .models import GradeBreakdown
        GradeBreakdown.objects.create(team_grade=self.grade, evaluation_type='panel',
            criterion_name='Legacy score', score=8, max_score=10)
        scores = self.serialized()['panel_evaluation_scores']
        self.assertEqual(len(scores), 1)
        self.assertEqual(scores[0]['percentage'], '80.00')

    def test_model_display_and_report_data_do_not_include_access_credentials(self):
        self.submit_guest()
        submission = self.grade.panelist_submissions.get(guest_code_id=str(self.invitation.pk))
        self.assertNotIn(self.invitation.code, str(submission))
        from reports.assessment_reports import _team_rows
        from reports.assessment_workbooks import assessment_document_sheets
        from reports.generators.team_grade_report import generate_team_grade_pdf
        rows = _team_rows(self.grade)
        self.assertIn(self.evaluator.name, str(rows))
        self.assertNotIn(self.invitation.code, str(rows))
        sheets = assessment_document_sheets([self.grade], student=None, team_rows=_team_rows, coverage='latest')
        self.assertNotIn(self.invitation.code, str(sheets))
        import io
        import pdfplumber
        pdf = generate_team_grade_pdf(self.grade, self.admin)
        with pdfplumber.open(io.BytesIO(pdf)) as document:
            text = '\n'.join(page.extract_text() or '' for page in document.pages)
        self.assertIn(self.evaluator.name, text)
        self.assertNotIn(self.invitation.code, text)

    def test_discovery_matches_stage_label_and_pit_event_name_in_correct_term(self):
        self.assertEqual(automation.fetch_target_schedule_ids(stage=self.stage.label), [self.capstone_schedule.pk])
        self.assertEqual(automation.fetch_target_schedule_ids(stage='PIT Expo', scope='pit',
            semester_id=self.first_semester.pk), [self.pit_schedule.pk])
        self.assertEqual(automation.fetch_target_schedule_ids(scope='pit'), [])

    def test_discovery_does_not_fall_back_to_all_terms_without_active_semester(self):
        with patch('academic_period_management.services.active_semester', return_value=None), self.assertRaises(ValueError):
            automation.fetch_target_schedule_ids()

    def test_discovery_deduplicates_and_never_includes_another_session(self):
        invitation = automation.fetch_external_panelists([self.capstone_schedule.pk])
        self.assertEqual(len(invitation), 1)
        self.assertEqual(automation.fetch_external_panelists([self.pit_schedule.pk]), [])

    def test_faculty_token_generation_does_not_write_refresh_tokens(self):
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
        before = OutstandingToken.objects.count()
        self.assertTrue(automation.get_jwt_token_for_user(self.panelist.username))
        self.assertEqual(OutstandingToken.objects.count(), before)
