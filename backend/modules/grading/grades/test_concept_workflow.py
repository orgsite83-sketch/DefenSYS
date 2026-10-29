from datetime import timedelta
from unittest.mock import patch
from tempfile import TemporaryDirectory
from pathlib import Path
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import StageDeliverable
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound
from repository.deliverables.services import upsert_submission, review_submission, endorse_team
from student_teams.models import TeamStageProgress
from student_teams.services import is_stage_ready
from . import workflow_tests as workflow_fixtures
from .services import GradeContextService


class ConceptHearingWorkflowTests(APITestCase):
    _rubric = workflow_fixtures.DefenseWorkflowTests._rubric
    submit_panel = workflow_fixtures.DefenseWorkflowTests.submit_panel

    def setUp(self):
        # These fixtures describe captured v1 title review. Title-first behavior
        # is exercised by repository title-workflow regressions separately.
        legacy_titles = override_settings(DEFENSYS_TITLE_WORKFLOW_VERSION=1)
        legacy_titles.enable()
        self.addCleanup(legacy_titles.disable)
        workflow_fixtures.DefenseWorkflowTests.setUp(self)
        temporary_root = Path(__file__).resolve().parents[4] / '.tmp'
        temporary_root.mkdir(exist_ok=True)
        media = TemporaryDirectory(dir=temporary_root)
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name)
        settings.enable()
        self.addCleanup(settings.disable)
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        self.stage.deliverables.all().delete()
        self.paper = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='CONCEPTS',
            label='Concept papers', required=True, is_defense_material=True,
            file_policy={'mode': 'concepts'})
        # Finish configuring this fixture before its first paper/review. The
        # shared grading fixture has already allocated a provisional schedule.
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        TeamStageProgress.objects.filter(team=self.capstone_team, defense_stage=self.stage).delete()
        extraction = patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object',
                           return_value={'text': 'Concept paper fixture'})
        extraction.start()
        self.addCleanup(extraction.stop)
        self.prepare()
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        concepts.bind_schedule(self.capstone_schedule)

    def prepare(self, accepted=True):
        concepts.save_titles(self.capstone_team, self.stage,
            [{'key': f'c{i}', 'title': f'Concept project {i}'} for i in range(1, 4)])
        for i in range(1, 4):
            sub = upsert_submission(self.capstone_team, self.stage.label, 'CONCEPTS', f'paper-{i}.pdf', '10 B', self.student,
                file=SimpleUploadedFile(f'paper-{i}.pdf', b'concept fixture'), slot_key=f'c{i}:paper')
            if accepted:
                review_submission(self.capstone_team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser,
                    file_id=sub.files.get(slot_key=f'c{i}:paper', is_current=True).pk)

    def verdict(self, *, approved=False, verdict=None, verification_required=False):
        self.submit_panel()
        self.client.force_authenticate(self.admin)
        decisions = [{'key': f'c{i}', 'decision': 'approved' if approved and i == 2 else 'rejected',
                      'remarks': 'Documented concept decision.', 'next_action': 'omit' if approved else 'replace'} for i in range(1, 4)]
        return self.client.patch(f'/api/defense/schedules/{self.capstone_schedule.pk}/verdict/', {
            'verdict': verdict or ('approved' if approved else 'for_redefense'),
            'verdict_remarks': 'Documented hearing outcome.', 'concept_decisions': decisions,
            'redefense_verification_required': verification_required}, format='json')

    def test_all_rejected_requires_fresh_review_then_creates_second_assessed_attempt(self):
        response = self.verdict()
        self.assertEqual(response.status_code, 200, response.data)
        self.capstone_team.refresh_from_db()
        self.assertNotEqual(self.capstone_team.status, 'Failed')
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        first = ConceptRound.objects.get(team=self.capstone_team, number=1)
        old_urls = [f['file_url'] for g in first.documents_snapshot for f in g['files']]
        self.prepare(accepted=False)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        sub = self.capstone_team.deliverable_submissions.get(deliverable_id='CONCEPTS')
        for row in sub.files.filter(is_current=True):
            review_submission(self.capstone_team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser, file_id=row.pk)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))
        next_schedule = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date=self.capstone_schedule.scheduled_date + timedelta(days=7),
            start_time='11:00', room='Second hearing room')
        grade, _, _ = GradeContextService.get_or_create_for_schedule(next_schedule)
        self.assertEqual(grade.attempt_count, 2)
        self.assertEqual(grade.verdict, '')
        self.assertIsNone(grade.adviser_score)
        self.assertIsNone(grade.peer_score)
        self.assertEqual(grade.attempt_history.get().verdict, 'for_redefense')
        self.assertEqual(grade.attempt_history.get().adviser_score, 84)
        first.refresh_from_db()
        self.assertEqual(old_urls, [f['file_url'] for g in first.documents_snapshot for f in g['files']])
        self.assertEqual(concepts.latest_round(self.capstone_team, self.stage).schedule_id, next_schedule.pk)

    def test_selected_concept_becomes_the_official_project_without_advancing_stage(self):
        response = self.verdict(approved=True)
        self.assertEqual(response.status_code, 200, response.data)
        self.capstone_team.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertEqual(self.capstone_team.project_title, 'Concept project 2')
        self.assertEqual(self.capstone_team.project_version, 1)
        self.assertEqual(self.grade.project_title_snapshot, 'Concept project 2')
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))

    def test_inconsistent_hearing_verdict_rolls_back_concept_and_grade_changes(self):
        response = self.verdict(verdict='approved')
        self.assertEqual(response.status_code, 400)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual(ConceptRound.objects.filter(team=self.capstone_team).count(), 1)

    def test_admin_exception_requires_documents_and_reason_and_is_audited(self):
        self.assertEqual(self.verdict().status_code, 200)
        with self.assertRaises(ValueError):
            concepts.override_clearance(self.capstone_team, self.stage, self.admin, 'Approved urgent hearing.')
        self.prepare(accepted=False)
        with self.assertRaises(ValueError):
            concepts.override_clearance(self.capstone_team, self.stage, self.admin, '')
        with self.assertRaises(ValueError):
            concepts.override_clearance(self.capstone_team, self.stage, self.admin, 'Committee authorized urgent review.')
        self.prepare(accepted=True)
        concepts.override_clearance(self.capstone_team, self.stage, self.admin, 'Committee authorized urgent review.')
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))
        from authentication_access_control.models import SystemAuditLog
        self.assertTrue(SystemAuditLog.objects.filter(action='repository.concept_clearance_override').exists())

    def test_retired_panel_requested_policy_cannot_skip_repeat_review(self):
        self.stage.concept_config['review_policy'] = 'panel_requested'
        self.stage.save()
        self.assertEqual(self.verdict().status_code, 200)
        self.prepare(accepted=False)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        self.prepare(accepted=True)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))

    def test_adviser_endorsement_satisfies_requested_concept_verification(self):
        self.stage.concept_config['review_policy'] = 'panel_requested'
        self.stage.save()
        self.assertEqual(self.verdict(verification_required=True).status_code, 200)
        self.prepare(accepted=True)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.redefense_verified_by_id, self.adviser.pk)

    def test_panel_can_view_all_three_papers_and_historical_hearing_keeps_original_files(self):
        from defense.scheduler.views import _team_assignment_payload
        before = _team_assignment_payload(self.capstone_schedule, team_grade=self.grade)
        self.assertEqual(len(before['defense_materials']), 3)
        self.assertEqual(self.verdict().status_code, 200)
        self.prepare(accepted=False)
        after = _team_assignment_payload(self.capstone_schedule, team_grade=self.grade)
        self.assertEqual([f['file_url'] for f in before['defense_materials']], [f['file_url'] for f in after['defense_materials']])
