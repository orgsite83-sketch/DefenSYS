"""Deadline lifecycle, management readiness, and term-scoped instructor regressions."""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule
from defense.scheduler.operations import deletion_preview
from grading.grades.models import PanelistGradeSubmission, TeamGrade
from student_teams.models import StudentTeam
from user_management.models import SectionInstructorAssignment
from . import test_submission_timing as fixtures
from .services import resolve_team_instructor_or_adviser_name
from .timing import defense_starts_at, materials_readiness


class FeatureRegressionTests(APITestCase):
    setUp = fixtures.SubmissionTimingTests.setUp
    upload = fixtures.SubmissionTimingTests.upload
    clear_and_endorse = fixtures.SubmissionTimingTests.clear_and_endorse
    schedule = fixtures.SubmissionTimingTests.schedule
    extension = fixtures.SubmissionTimingTests.extension

    def test_rescheduling_expires_old_material_permissions_with_partial_save(self):
        schedule = self.schedule()
        deadline = timezone.now() + timedelta(days=8)
        self.assertEqual(self.extension(schedule, deadline, mode='late_upload').status_code, 200)
        schedule.refresh_from_db()
        schedule.materials_deadline_override = defense_starts_at(schedule)
        schedule.materials_notice_key = 'previous-notice'
        schedule.save()
        schedule.scheduled_date += timedelta(days=1)
        schedule.save(update_fields=['scheduled_date'])
        schedule.refresh_from_db()
        self.assertIsNone(schedule.materials_late_upload_until)
        self.assertIsNone(schedule.materials_deadline_override)
        self.assertEqual(schedule.materials_deadline_reason, '')
        self.assertEqual(schedule.materials_notice_key, '')

    def test_archiving_defense_closes_late_uploads_in_api_and_readiness(self):
        schedule = self.schedule()
        schedule.status = DefenseSchedule.STATUS_DONE
        schedule.save()
        self.assertEqual(self.extension(schedule, timezone.now() + timedelta(days=8),
            mode='late_upload').status_code, 200)
        response = self.client.patch(f'/api/defense/board/{schedule.pk}/', {'status': 'archived'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        schedule.refresh_from_db()
        readiness = materials_readiness(schedule)
        self.assertFalse(readiness['late_window_active'])
        self.assertFalse(readiness['can_open_late_window'])
        self.assertTrue(readiness['is_locked_historical'])
        self.assertNotEqual(readiness['items'][0]['upload_lock_reason'], '')
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'DECK',
            'file_name': 'pitch.pptx', 'file_size': '7 B',
            'file': SimpleUploadedFile('pitch.pptx', b'content')}, format='multipart')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('archived', response.data['detail'])

    def test_publishing_grades_closes_a_previously_opened_window(self):
        schedule = self.schedule()
        self.assertEqual(self.extension(schedule, timezone.now() + timedelta(days=8),
            mode='late_upload').status_code, 200)
        TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            schedule=schedule, panel_score=80, peer_score=80, adviser_score=80, status=TeamGrade.STATUS_PUBLISHED)
        schedule.refresh_from_db()
        readiness = materials_readiness(schedule)
        self.assertTrue(readiness['is_locked_historical'])
        self.assertFalse(readiness['late_window_active'])
        with self.assertRaisesRegex(PermissionError, 'finalized'):
            self.upload()

    def test_preview_detects_evaluations_and_published_locks_without_prefetch(self):
        schedule = self.schedule()
        panelist = get_user_model().objects.create_user(username='regression-panel', role='faculty', is_panelist=True)
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester,
            schedule=schedule, defense_stage=self.stage)
        evaluation = PanelistGradeSubmission.objects.create(team_grade=grade, schedule=schedule, panelist=panelist)
        preview = deletion_preview([DefenseSchedule.objects.get(pk=schedule.pk)])['entries'][0]
        self.assertTrue(preview['has_evaluations'])
        self.assertFalse(preview['can_extend_deadline'])
        self.assertTrue(preview['can_open_late_window'])
        evaluation.is_void = True
        evaluation.save(update_fields=['is_void'])
        self.assertFalse(materials_readiness(schedule)['has_evaluations'])
        grade.panel_score = grade.peer_score = grade.adviser_score = 80
        grade.status = TeamGrade.STATUS_PUBLISHED
        grade.save()
        preview = deletion_preview([DefenseSchedule.objects.get(pk=schedule.pk)])['entries'][0]
        self.assertTrue(preview['is_locked_historical'])
        self.assertFalse(preview['can_open_late_window'])

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

    def test_reschedule_and_explicit_deadline_are_saved_together(self):
        schedule = self.schedule()
        new_date = schedule.scheduled_date + timedelta(days=1)
        new_deadline = defense_starts_at(schedule) + timedelta(days=1, hours=-2)
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/board/operations/', {
            'action': 'update', 'anchor_id': schedule.pk, 'expected_revisions': {str(schedule.pk): schedule.revision},
            'reason': 'Rescheduled defense with a newly reviewed cutoff.', 'changes': {
                'scheduled_date': new_date.isoformat(), 'materials_deadline_mode': 'extend',
                'materials_deadline': new_deadline.isoformat()}}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        schedule.refresh_from_db()
        self.assertEqual(schedule.scheduled_date, new_date)
        self.assertEqual(schedule.materials_deadline_override, new_deadline)

    def test_past_project_cannot_receive_a_new_late_upload_permission(self):
        schedule = self.schedule()
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        response = self.extension(schedule, timezone.now() + timedelta(days=8), mode='late_upload')
        self.assertEqual(response.status_code, 400, response.data)
        schedule.refresh_from_db()
        self.assertIsNone(schedule.materials_late_upload_until)
