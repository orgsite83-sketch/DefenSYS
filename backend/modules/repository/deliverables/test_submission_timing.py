"""Pre-defense acceptance, scheduling guards and reusable document fixtures."""
from datetime import time, timedelta
from tempfile import TemporaryDirectory
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from grading.rubrics.models import Rubric, RubricCriterion
from defense.stages.serializers import DefenseStageWriteSerializer, StageDeliverableSerializer
from student_teams.models import StudentTeam, TeamMembership
from .services import endorse_team, required_complete, upsert_submission, review_submission


class SubmissionTimingTests(APITestCase):
    def setUp(self):
        version = self.settings(DEFENSYS_TITLE_WORKFLOW_VERSION=1)
        version.enable()
        self.addCleanup(version.disable)
        temporary_root = Path(__file__).resolve().parents[4] / '.tmp'
        temporary_root.mkdir(exist_ok=True)
        self.media = TemporaryDirectory(dir=temporary_root)
        self.addCleanup(self.media.cleanup)
        self.settings_override = override_settings(MEDIA_ROOT=self.media.name)
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        users = get_user_model()
        self.admin = users.objects.create_user(username='timing-admin', role='admin')
        self.adviser = users.objects.create_user(username='timing-adviser', role='faculty', is_adviser=True)
        self.student = users.objects.create_user(username='timing-student', role='student')
        year = SchoolYear.objects.create(label='2030-2031')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.stage, _ = DefenseStage.objects.get_or_create(label='Concept Proposal', defaults={'display_order': 1})
        self.stage.deliverables.all().delete()
        extraction = patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object',
                           return_value={'text': 'Uploaded test material'})
        extraction.start()
        self.addCleanup(extraction.stop)
        self.paper = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='PAPER',
            label='Concept paper', required=True)
        self.deck = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='DECK',
            label='Pitch deck', required=True, requirement_timing='defense', deadline_hours_before=24,
            is_defense_material=True, file_format='presentation')
        self.team = StudentTeam.objects.create(name='Timing Team', project_title='Scheduling Materials',
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', semester=self.semester,
            leader=self.student, adviser=self.adviser, status=StudentTeam.STATUS_APPROVED)
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        self.now = timezone.now()
        self.date = timezone.localdate(self.now) + timedelta(days=5)

    def upload(self, number='DECK', name='pitch.pptx'):
        return upsert_submission(self.team, self.stage.label, number, name, '10 B', self.student,
            file=SimpleUploadedFile(name, b'presentation content', content_type='application/octet-stream'))

    def clear_and_endorse(self):
        self.upload('PAPER', 'paper.docx')
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser)
        if self.deck.required:
            # Simulate a clearance already recorded before unified review.
            from student_teams.services import mark_stage_ready
            mark_stage_ready(self.team, self.stage, self.adviser)
        else:
            endorse_team(self.team, self.stage.label)

    def schedule(self):
        self.clear_and_endorse()
        return DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time=time(9), room='Room 201', created_by=self.admin)


    def test_all_required_pre_defense_files_need_acceptance(self):
        self.upload('PAPER', 'paper.docx')
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser)
        self.assertFalse(required_complete(self.team, self.stage.label))
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label)
        self.upload('DECK', 'pitch.pptx')
        self.assertFalse(required_complete(self.team, self.stage.label))
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        endorse_team(self.team, self.stage.label)
        self.assertTrue(required_complete(self.team, self.stage.label))


    def test_new_schedule_rechecks_legacy_endorsement_missing_required_deck(self):
        self.clear_and_endorse()
        rubric = Rubric.objects.create(name='Timing Panel Rubric', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type='panel', status='published', created_by=self.admin)
        RubricCriterion.objects.create(rubric=rubric, name='Presentation', scale=Rubric.SCALE_10, max_score=10)
        adviser_rubric = Rubric.objects.create(name='Timing Adviser Rubric', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type=Rubric.EVAL_ADVISER, status='published', created_by=self.admin)
        peer_rubric = Rubric.objects.create(name='Timing Peer Rubric', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type=Rubric.EVAL_PEER, status='published', created_by=self.admin)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester,
            panel_rubric=rubric, adviser_rubric=adviser_rubric, peer_rubric=peer_rubric,
            panel_weight=100, adviser_weight=0, peer_weight=0)
        panelist = get_user_model().objects.create_user(username='timing-panelist', role='faculty', is_panelist=True)
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/schedules/', {
            'scope': 'capstone', 'semester_id': self.semester.pk, 'team_id': self.team.pk,
            'defense_stage_id': self.stage.pk, 'rubric_id': rubric.pk, 'panelist_ids': [panelist.pk],
            'chair_panelist_id': panelist.pk, 'scheduled_date': self.date.isoformat(),
            'start_time': '09:00', 'room': 'Room 201', 'slot_duration': 60}, format='json')
        self.assertEqual(response.status_code, 400, response.data)


    def test_configuration_defaults_preserve_existing_gates_and_reject_bad_timing(self):
        self.assertEqual(self.paper.requirement_timing, 'scheduling')
        for bad in ({'requirement_timing': 'unknown'}, {'deadline_hours_before': -1},
                    {'deadline_hours_before': 721}, {'deliverable_type': 'post', 'requirement_timing': 'defense'}):
            serializer = StageDeliverableSerializer(data={'deliverable_id': 'X', 'label': 'Invalid', **bad})
            self.assertFalse(serializer.is_valid(), bad)
        serializer = DefenseStageWriteSerializer(data={'label': 'Invalid timed stage', 'deliverables': [
            {'deliverable_id': 'X', 'label': 'Invalid', 'requirement_timing': 'defense', 'deadline_hours_before': -1}]})
        self.assertFalse(serializer.is_valid())


def faculty_review_setup(case):
    """General document fixtures do not need an unrelated required deck."""
    SubmissionTimingTests.setUp(case)
    case.deck.required = False
    case.deck.save(update_fields=['required'])
