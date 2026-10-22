from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import PitEventDeliverable, PitEventGradingConfig
from defense.stages.models import StageDeliverable
from .endorsement import endorsement_review, review_and_endorse, StaleEndorsementReview
from .models import DeliverableSubmission
from .services import required_complete, review_submission, stage_payload
from . import test_submission_timing as timing_tests


class ReviewEndorsementTests(APITestCase):
    setUp = timing_tests.faculty_review_setup
    upload = timing_tests.SubmissionTimingTests.upload

    def review(self):
        return endorsement_review(self.team, self.stage.label)

    def endorse(self, token=None, actor=None):
        return review_and_endorse(self.team, self.stage.label, actor=actor or self.adviser,
                                 review_token=token or self.review()['review_token'])

    def make_pit(self):
        self.team.level = self.team.LEVEL_1_PIT
        self.team.year_level = '1st Year'
        self.team.save()
        self.adviser.is_pit_lead = True
        self.adviser.pit_lead_year = '1st Year'
        self.adviser.save()
        event = PitEventGradingConfig.objects.create(year_level='1st Year', semester=self.semester, event_name=self.stage.label)
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='PAPER', label='Concept paper', required=True)
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='DECK', label='Pitch deck', required=False,
                                          requirement_timing='defense', file_format='presentation')

    def assert_separate_review_and_endorsement(self):
        paper = self.upload('PAPER', 'paper.docx')
        payload = {'team_id': self.team.pk, 'stage_label': self.stage.label}
        self.client.force_authenticate(self.adviser)

        def endorse():
            return self.client.post('/api/repository/deliverables/endorse/', payload, format='json')

        def review(status, feedback=''):
            return self.client.post('/api/repository/deliverables/review/', {
                **payload, 'deliverable_id': 'PAPER', 'status': status, 'feedback': feedback,
            }, format='json')

        self.assertEqual(endorse().status_code, 400)
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'pending')
        self.assertEqual(review('accepted').status_code, 200)
        self.team.refresh_from_db()
        self.assertFalse(self.team.ready_for_stage)
        self.assertTrue(required_complete(self.team, self.stage.label))

        self.assertEqual(review('rejected', 'Clarify the architecture.').status_code, 200)
        self.assertEqual(endorse().status_code, 400)
        self.upload('PAPER', 'corrected.docx')
        self.assertEqual(endorse().status_code, 400)
        self.assertEqual(review('accepted').status_code, 200)
        self.assertEqual(endorse().status_code, 200)
        self.team.refresh_from_db()
        paper.refresh_from_db()
        self.assertEqual(self.team.ready_for_stage, self.stage.label)
        self.assertEqual(paper.status, 'accepted')
        self.assertEqual(paper.reviewed_by, self.adviser)
        if self.team.is_capstone:
            from student_teams.models import TeamStageProgress
            progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage, semester=self.semester)
            self.assertEqual(progress.updated_by, self.adviser)
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.review_and_endorse').exists())
        self.assertEqual(stage_payload(self.team, self.stage.label)['materials_readiness']['submitted_total'], 0)

    def test_capstone_reviews_files_before_separate_endorsement(self):
        self.assert_separate_review_and_endorsement()

    def test_pit_reviews_files_before_separate_endorsement(self):
        self.make_pit()
        self.assert_separate_review_and_endorsement()

    def test_pending_scheduling_files_are_approved_and_endorsed_together_for_both_tracks(self):
        for pit in (False, True):
            with self.subTest(pit=pit):
                if pit:
                    # A separate team identity keeps prior Capstone progress out of the PIT scenario.
                    from student_teams.models import StudentTeam
                    self.team = StudentTeam.objects.create(name='PIT review team', project_title='PIT review project',
                        level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester,
                        leader=self.student, adviser=self.adviser, status=StudentTeam.STATUS_APPROVED)
                    self.make_pit()
                paper = self.upload('PAPER', 'paper.docx')
                deck = self.upload()
                self.assertFalse(required_complete(self.team, self.stage.label))
                review = stage_payload(self.team, self.stage.label)['endorsement_review']
                self.assertTrue(review['can_review_and_endorse'])
                self.assertEqual([f['id'] for f in review['files']], ['PAPER'])
                self.endorse(review['review_token'])
                paper.refresh_from_db()
                deck.refresh_from_db()
                self.team.refresh_from_db()
                self.assertEqual(paper.status, 'accepted')
                self.assertEqual(paper.reviewed_by, self.adviser)
                self.assertIsNotNone(paper.reviewed_at)
                self.assertEqual(deck.status, 'pending')
                self.assertEqual(self.team.ready_for_stage, self.stage.label)
                self.assertTrue(required_complete(self.team, self.stage.label))
        logs = SystemAuditLog.objects.filter(action='repository.review_and_endorse')
        self.assertEqual(logs.count(), 2)
        self.assertEqual(logs.filter(new_values__track='pit').count(), 1)

    def test_missing_deck_does_not_block_but_missing_or_rejected_paper_does(self):
        self.assertFalse(self.review()['can_review_and_endorse'])
        paper = self.upload('PAPER', 'paper.docx')
        self.assertTrue(self.review()['can_review_and_endorse'])
        review_submission(self.team, self.stage.label, 'PAPER', 'rejected', 'Fix scope', self.adviser)
        self.assertFalse(self.review()['can_review_and_endorse'])
        with self.assertRaises(ValueError):
            self.endorse('old-token')
        self.upload('PAPER', 'corrected.docx')
        self.endorse()
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'accepted')

    def test_metadata_alone_cannot_be_approved(self):
        DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label, deliverable_id='PAPER',
                                            label='Concept paper', file_name='missing.docx', deliverable_type='pre')
        self.assertFalse(self.review()['can_review_and_endorse'])

    def test_replacement_or_checklist_change_requires_fresh_review(self):
        paper = self.upload('PAPER', 'paper.docx')
        token = self.review()['review_token']
        self.upload('PAPER', 'replacement.docx')
        with self.assertRaises(StaleEndorsementReview):
            self.endorse(token)
        token = self.review()['review_token']
        self.paper.label = 'Revised concept paper'
        self.paper.save()
        with self.assertRaises(StaleEndorsementReview):
            self.endorse(token)
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'pending')

    def test_progression_failure_rolls_back_file_acceptance(self):
        paper = self.upload('PAPER', 'paper.docx')
        with patch('repository.deliverables.services.mark_stage_ready', side_effect=ValueError('Progression blocked')):
            with self.assertRaisesMessage(ValueError, 'Progression blocked'):
                self.endorse()
        paper.refresh_from_db()
        self.team.refresh_from_db()
        self.assertEqual(paper.status, 'pending')
        self.assertIsNone(paper.reviewed_by)
        self.assertFalse(self.team.ready_for_stage)

    def test_audit_failure_rolls_back_acceptance_and_endorsement(self):
        paper = self.upload('PAPER', 'paper.docx')
        with patch('repository.deliverables.endorsement.log_high_impact_action', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(RuntimeError):
                self.endorse()
        paper.refresh_from_db()
        self.team.refresh_from_db()
        self.assertEqual(paper.status, 'pending')
        self.assertFalse(self.team.ready_for_stage)

    def test_previously_accepted_files_keep_their_reviewer_and_feedback(self):
        paper = self.upload('PAPER', 'paper.docx')
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', 'Original approval', self.admin)
        paper.refresh_from_db()
        reviewed_at = paper.reviewed_at
        self.endorse()
        paper.refresh_from_db()
        self.assertEqual(paper.reviewed_by, self.admin)
        self.assertEqual(paper.reviewed_at, reviewed_at)
        self.assertEqual(paper.feedback, 'Original approval')

    def test_optional_and_post_defense_files_are_excluded(self):
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='OPT', label='Optional', required=False)
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='POST', label='Final', deliverable_type='post')
        paper = self.upload('PAPER', 'paper.docx')
        optional = self.upload('OPT', 'optional.docx')
        self.endorse()
        optional.refresh_from_db()
        self.assertEqual(optional.status, 'pending')
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'accepted')

    def test_api_requires_snapshot_and_assigned_faculty_or_admin(self):
        self.upload('PAPER', 'paper.docx')
        payload = {'team_id': self.team.pk, 'stage_label': self.stage.label, 'review_token': self.review()['review_token']}
        self.client.force_authenticate(self.student)
        self.assertEqual(self.client.post('/api/repository/deliverables/review-endorse/', payload, format='json').status_code, 403)
        other = get_user_model().objects.create_user(username='other-reviewer', role='faculty', is_adviser=True)
        self.client.force_authenticate(other)
        self.assertEqual(self.client.post('/api/repository/deliverables/review-endorse/', payload, format='json').status_code, 404)
        self.client.force_authenticate(self.adviser)
        bad_payload = {**payload, 'review_token': 'tampered'}
        self.assertEqual(self.client.post('/api/repository/deliverables/review-endorse/', bad_payload, format='json').status_code, 409)
        self.assertEqual(self.client.post('/api/repository/deliverables/review-endorse/', payload, format='json').status_code, 200)
        self.assertEqual(self.client.post('/api/repository/deliverables/review-endorse/', payload, format='json').status_code, 400)

    def test_inactive_semester_is_read_only(self):
        self.upload('PAPER', 'paper.docx')
        token = self.review()['review_token']
        self.semester.is_active = False
        self.semester.save()
        self.team.refresh_from_db()
        with self.assertRaises(ValueError):
            self.endorse(token)

    def test_pit_lead_must_match_year_and_section_instructor_can_endorse_assigned_team(self):
        from user_management.models import SectionInstructorAssignment
        self.make_pit()
        self.team.adviser = None
        self.team.section = 'BSIT-1A'
        self.team.save()
        self.upload('PAPER', 'paper.docx')
        wrong = get_user_model().objects.create_user(username='wrong-pit-year', role='faculty',
                                                     is_pit_lead=True, pit_lead_year='2nd Year')
        with self.assertRaises(PermissionError):
            self.endorse(actor=wrong)
        instructor = get_user_model().objects.create_user(username='review-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.semester,
            year_level='1st Year', section='BSIT-1A', is_active=True)
        self.endorse(actor=instructor)
        self.assertTrue(required_complete(self.team, self.stage.label))

    def test_a_previous_project_snapshot_cannot_approve_current_files(self):
        paper = self.upload('PAPER', 'paper.docx')
        token = self.review()['review_token']
        self.team.project_version += 1
        self.team.save()
        with self.assertRaises(ValueError):
            self.endorse(token)
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'pending')

    def test_scheduled_defense_and_official_completion_block_combined_action(self):
        from defense.scheduler.models import DefenseSchedule
        from defense.stages.models import StageGradingConfig
        from datetime import time
        paper = self.upload('PAPER', 'paper.docx')
        token = self.review()['review_token']
        DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time=time(9), room='Room 201', created_by=self.admin)
        with self.assertRaises(ValueError):
            self.endorse(token)
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'pending')
        DefenseSchedule.objects.filter(team=self.team).delete()
        config, _ = StageGradingConfig.objects.get_or_create(defense_stage=self.stage, semester=self.semester)
        config.is_officially_complete = True
        config.save()
        self.assertFalse(self.review()['can_review_and_endorse'])

    def test_pre_defense_corrections_require_fresh_acceptance(self):
        self.deck.required = True
        self.deck.save()
        self.upload('PAPER', 'paper.docx')
        deck = self.upload()
        self.endorse()
        self.team.refresh_from_db()
        from .services import unendorse_team
        unendorse_team(self.team, self.stage.label)
        review_submission(self.team, self.stage.label, 'DECK', 'rejected', 'Add the demo flow', self.adviser)
        self.team.refresh_from_db()
        self.assertIsNone(self.team.ready_for_stage)
        self.upload(name='corrected.pptx')
        deck.refresh_from_db()
        self.assertEqual(deck.status, 'pending')
        self.assertFalse(required_complete(self.team, self.stage.label))
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        self.assertTrue(required_complete(self.team, self.stage.label))
