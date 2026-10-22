"""Scheduling clearance and presentation uploads follow independent gates."""
from datetime import datetime, time, timedelta
from tempfile import TemporaryDirectory
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.materials import sync_overdue_notifications, extend_material_deadline
from defense.scheduler.models import DefenseSchedule, PitEventDeliverable, PitEventGradingConfig
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from defense.scheduler.serializers import DefenseScheduleSerializer
from grading.rubrics.models import Rubric, RubricCriterion
from defense.stages.serializers import DefenseStageWriteSerializer, StageDeliverableSerializer
from notifications.models import Notification
from student_teams.models import StudentTeam, TeamMembership
from .models import DeliverableSubmission
from .services import endorse_team, required_complete, upsert_submission, review_submission, remove_submission, stage_payload
from .timing import deadline_for, materials_readiness, stage_schedule


class SubmissionTimingTests(APITestCase):
    def setUp(self):
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
        return create_legacy_schedule(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time=time(9), room='Room 201', created_by=self.admin)

    def extension(self, schedule, deadline, **extra):
        self.client.force_authenticate(self.admin)
        return self.client.post(f'/api/defense/schedules/{schedule.pk}/material-deadline/', {
            'deadline': deadline.isoformat(), 'reason': 'Approved a late presentation upload.',
            'revision': schedule.revision, **extra}, format='json')

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

    def test_endorsed_team_can_upload_and_update_deck_without_reendorsing(self):
        schedule = self.schedule()
        deck = self.upload()
        # Optional faculty approval does not freeze a presentation before cutoff.
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        self.upload(name='updated.pptx')
        deck.refresh_from_db()
        self.assertEqual(deck.file_name, 'updated.pptx')
        self.assertEqual(materials_readiness(schedule)['status'], 'ready')
        self.team.refresh_from_db()
        self.assertEqual(self.team.ready_for_stage, self.stage.label)
        with self.assertRaises(PermissionError):
            self.upload('PAPER', 'changed.docx')

    def test_cutoff_locks_upload_replacement_and_removal_including_revision_requests(self):
        schedule = self.schedule()
        self.upload()
        deadline = deadline_for({'type': 'pre', 'requirement_timing': 'defense', 'deadline_hours_before': 24}, schedule)
        with patch('django.utils.timezone.now', return_value=deadline):
            with self.assertRaises(PermissionError):
                self.upload(name='late.pptx')
            with self.assertRaises(PermissionError):
                remove_submission(self.team, self.stage.label, 'DECK')
            DeliverableSubmission.objects.filter(deliverable_id='DECK').update(status='rejected', revision_review_unlocked=True)
            with self.assertRaises(PermissionError):
                self.upload(name='revision.pptx')
        schedule.refresh_from_db()
        self.assertEqual(schedule.status, 'scheduled')

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

    def test_grace_audit_failure_rolls_back_the_deadline_revision_and_notifications(self):
        schedule = self.schedule()
        start = timezone.make_aware(datetime.combine(self.date, time(9)))
        count = Notification.objects.count()
        with patch('defense.scheduler.materials.log_high_impact_action', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(RuntimeError):
                extend_material_deadline(self.admin, schedule.pk, {'deadline': start, 'revision': 1,
                    'reason': 'Approved preparation grace period.'})
        schedule.refresh_from_db()
        self.assertIsNone(schedule.materials_deadline_override)
        self.assertEqual(schedule.revision, 1)
        self.assertEqual(Notification.objects.count(), count)

    def test_material_queries_are_batched_and_historical_projects_keep_their_own_files(self):
        schedule = self.schedule()
        self.upload()
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        self.assertEqual(materials_readiness(schedule)['status'], 'ready')
        serializer = DefenseScheduleSerializer([schedule, schedule], many=True)
        with CaptureQueriesContext(connection) as queries:
            for record in serializer.instance:
                self.assertEqual(serializer.child.get_materials_readiness(record)['status'], 'ready')
        # Definitions, files and the added permission facts remain batched.
        self.assertLessEqual(len(queries), 4)

    def test_grace_deadline_reopens_only_materials_and_captures_reason_and_audit(self):
        schedule = self.schedule()
        start = timezone.make_aware(datetime.combine(self.date, time(9)))
        cutoff = start - timedelta(hours=24)
        with patch('django.utils.timezone.now', return_value=cutoff + timedelta(hours=1)):
            response = self.extension(schedule, start - timedelta(hours=2))
            self.assertEqual(response.status_code, 200, response.data)
            self.upload()
            with self.assertRaises(PermissionError):
                self.upload('PAPER', 'changed.docx')
        schedule.refresh_from_db()
        self.assertEqual(schedule.revision, 2)
        audit = SystemAuditLog.objects.get(action='schedule.material_deadline_extended')
        self.assertEqual(audit.reason, 'Approved a late presentation upload.')
        self.assertEqual(audit.new_values['scope'], 'capstone')
        self.client.force_authenticate(self.admin)
        response = self.client.get(f'/api/defense/board/operations/?history_for={schedule.pk}')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['history'][0]['changes'][0]['label'], 'Material submission deadline')
        self.assertTrue(Notification.objects.filter(title='Defense material deadline extended', recipient=self.student).exists())

    def test_extension_validates_authority_revision_and_defense_boundary(self):
        schedule = self.schedule()
        start = timezone.make_aware(datetime.combine(self.date, time(9)))
        self.assertEqual(self.extension(schedule, start + timedelta(hours=1)).status_code, 400)
        self.assertEqual(self.extension(schedule, start - timedelta(hours=2), revision=999).status_code, 409)
        self.assertEqual(self.extension(schedule, start - timedelta(hours=2), reason='').status_code, 400)
        self.client.force_authenticate(self.student)
        response = self.client.post(f'/api/defense/schedules/{schedule.pk}/material-deadline/', {
            'deadline': start.isoformat(), 'reason': 'Student tries to bypass the cutoff.', 'revision': 1}, format='json')
        self.assertEqual(response.status_code, 403)
        self.assertFalse(SystemAuditLog.objects.filter(action='schedule.material_deadline_extended').exists())

    def test_overdue_materials_are_independent_of_clearance_and_reminders_are_idempotent(self):
        schedule = self.schedule()
        cutoff = timezone.make_aware(datetime.combine(self.date, time(9))) - timedelta(hours=24)
        with patch('django.utils.timezone.now', return_value=cutoff + timedelta(minutes=1)):
            self.assertEqual(materials_readiness(schedule)['status'], 'overdue')
            self.assertTrue(required_complete(self.team, self.stage.label))
            self.assertEqual(sync_overdue_notifications(), 1)
            self.assertEqual(sync_overdue_notifications(), 0)
            alerts = Notification.objects.filter(title='Defense materials overdue')
            self.assertEqual(alerts.filter(recipient=self.student).count(), 1)
            self.assertEqual(alerts.filter(recipient=self.admin).count(), 1)
            self.client.force_authenticate(self.student)
            response = self.client.get('/api/notifications/?workspace=student')
            self.assertEqual(response.status_code, 200, response.data)
            alert = next(n for n in response.data['notifications'] if n['title'] == 'Defense materials overdue')
            self.assertNotEqual(alert.get('action', {}).get('status'), 'completed')
        schedule.refresh_from_db()
        self.assertEqual(schedule.status, 'scheduled')

    def test_rescheduling_recomputes_deadline_and_clears_grace(self):
        schedule = self.schedule()
        start = timezone.make_aware(datetime.combine(self.date, time(9)))
        self.assertEqual(self.extension(schedule, start - timedelta(hours=2)).status_code, 200)
        schedule.refresh_from_db()
        schedule.scheduled_date += timedelta(days=7)
        schedule.save()
        self.assertIsNone(schedule.materials_deadline_override)
        self.assertEqual(schedule.materials_deadline_reason, '')
        expected = start + timedelta(days=7) - timedelta(hours=24)
        self.assertEqual(deadline_for({'type': 'pre', 'requirement_timing': 'defense'}, schedule), expected)

    def test_actual_file_and_allowed_format_are_required(self):
        self.schedule()
        with self.assertRaises(ValueError):
            self.upload(name='script.exe')
        with self.assertRaises(ValueError):
            upsert_submission(self.team, self.stage.label, 'DECK', 'deck.pptx', '1 B', self.student)
        DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label, deliverable_id='DECK',
            label='Pitch deck', deliverable_type='pre', required=True, file_name='fake.pptx', status='accepted')
        self.assertEqual(materials_readiness(stage_schedule(self.team, self.stage.label))['submitted_total'], 0)

    def test_completed_or_old_project_schedule_cannot_reopen_materials(self):
        schedule = self.schedule()
        schedule.status = 'done'
        schedule.save()
        with self.assertRaises(PermissionError):
            self.upload()
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        self.assertIsNone(stage_schedule(self.team, self.stage.label))

    def test_configuration_defaults_preserve_existing_gates_and_reject_bad_timing(self):
        self.assertEqual(self.paper.requirement_timing, 'scheduling')
        for bad in ({'requirement_timing': 'unknown'}, {'deadline_hours_before': -1},
                    {'deadline_hours_before': 721}, {'deliverable_type': 'post', 'requirement_timing': 'defense'}):
            serializer = StageDeliverableSerializer(data={'deliverable_id': 'X', 'label': 'Invalid', **bad})
            self.assertFalse(serializer.is_valid(), bad)
        serializer = DefenseStageWriteSerializer(data={'label': 'Invalid timed stage', 'deliverables': [
            {'deliverable_id': 'X', 'label': 'Invalid', 'requirement_timing': 'defense', 'deadline_hours_before': -1}]})
        self.assertFalse(serializer.is_valid())

    def test_pit_uses_its_own_configuration_and_independent_deadlines(self):
        self.team.level = StudentTeam.LEVEL_3_PIT
        self.team.save(update_fields=['level'])
        event = PitEventGradingConfig.objects.create(year_level='3rd Year', semester=self.semester, event_name='3rd Year PIT Expo')
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='DECK', label='PIT pitch deck',
            required=True, requirement_timing='defense', deadline_hours_before=12)
        self.assertFalse(required_complete(self.team, event.event_name))
        # Preserve an endorsement made under the former deadline-only rule.
        from student_teams.pit_rosters import set_endorsed
        set_endorsed(self.team, event.event_name, True)
        schedule = create_legacy_schedule(team=self.team, semester=self.semester, scope='pit', event_name=event.event_name,
            scheduled_date=self.date, start_time=time(9), room='PIT Hall')
        payload = stage_payload(self.team, event.event_name)
        self.assertEqual(payload['required_total'], 0)
        self.assertEqual(payload['materials_readiness']['required_total'], 1)
        self.assertEqual(payload['materials_readiness']['items'][0]['due_at'],
            (timezone.make_aware(datetime.combine(self.date, time(9))) - timedelta(hours=12)).isoformat())
        old_deadline = payload['materials_readiness']['items'][0]['due_at']
        new_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.team.semester = new_term
        self.team.save(update_fields=['semester'])
        # The old PIT schedule keeps its original term's twelve-hour policy.
        self.assertEqual(materials_readiness(schedule)['items'][0]['due_at'], old_deadline)

    def test_late_upload_window_allows_missing_materials_and_sets_is_late(self):
        self.clear_and_endorse()
        past_date = timezone.localdate(self.now) - timedelta(days=1)
        schedule = create_legacy_schedule(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=past_date, start_time=time(9), room='Room 201', created_by=self.admin)

        future_window = timezone.now() + timedelta(hours=6)
        response = self.extension(schedule, future_window, mode='late_upload')
        self.assertEqual(response.status_code, 200)
        schedule.refresh_from_db()
        self.assertEqual(schedule.materials_late_upload_until, future_window)

        self.client.force_authenticate(self.student)
        response = self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'DECK',
            'file_name': 'late_pitch.pptx', 'file_size': '20 B',
            'file': SimpleUploadedFile('late_pitch.pptx', b'actual late presentation')}, format='multipart')
        self.assertEqual(response.status_code, 200)

        sub = DeliverableSubmission.objects.get(team=self.team, stage_label=self.stage.label, deliverable_id='DECK')
        self.assertTrue(sub.is_late)
        self.assertEqual(sub.file_name, 'late_pitch.pptx')

    def test_late_upload_window_blocks_replacement_of_existing_submissions(self):
        self.upload('DECK', 'initial_deck.pptx')
        self.clear_and_endorse()
        past_date = timezone.localdate(self.now) - timedelta(days=1)
        schedule = create_legacy_schedule(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=past_date, start_time=time(9), room='Room 201', created_by=self.admin)

        future_window = timezone.now() + timedelta(hours=6)
        response = self.extension(schedule, future_window, mode='late_upload')
        self.assertEqual(response.status_code, 200)

        self.client.force_authenticate(self.student)
        response = self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'DECK',
            'file_name': 'replaced_deck.pptx', 'file_size': '20 B',
            'file': SimpleUploadedFile('replaced_deck.pptx', b'new content')}, format='multipart')
        self.assertEqual(response.status_code, 400)
        self.assertIn('Existing submitted files are locked', response.data['detail'])

    def test_late_upload_window_preserves_evaluations(self):
        from grading.grades.models import TeamGrade, PanelistGradeSubmission
        from django.contrib.auth import get_user_model
        panelist = get_user_model().objects.create(username='test_eval_panelist', role='faculty', is_panelist=True)
        self.clear_and_endorse()
        past_date = timezone.localdate(self.now) - timedelta(days=1)
        schedule = create_legacy_schedule(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=past_date, start_time=time(9), room='Room 201', created_by=self.admin)
        team_grade = TeamGrade.objects.create(
            team=self.team, semester=self.semester, schedule=schedule,
            defense_stage=self.stage, stage_label=self.stage.label, status='draft',
        )
        eval_sub = PanelistGradeSubmission.objects.create(
            team_grade=team_grade, schedule=schedule, panelist=panelist, remarks='Strong presentation',
        )

        future_window = timezone.now() + timedelta(hours=6)
        response = self.extension(schedule, future_window, mode='late_upload')
        self.assertEqual(response.status_code, 200)

        self.client.force_authenticate(self.student)
        response = self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'DECK',
            'file_name': 'late_pitch.pptx', 'file_size': '20 B',
            'file': SimpleUploadedFile('late_pitch.pptx', b'late presentation')}, format='multipart')
        self.assertEqual(response.status_code, 200)

        eval_sub.refresh_from_db()
        self.assertFalse(eval_sub.is_void)
        self.assertEqual(eval_sub.remarks, 'Strong presentation')


def faculty_review_setup(case):
    """General document fixtures do not need an unrelated required deck."""
    SubmissionTimingTests.setUp(case)
    case.deck.required = False
    case.deck.save(update_fields=['required'])


def create_legacy_schedule(**kwargs):
    """Model a hearing scheduled before the Phase 1 data migration."""
    stage = kwargs.get('defense_stage')
    if stage:
        files = stage.deliverables.all()
    else:
        team = kwargs['team']
        config = PitEventGradingConfig.objects.filter(semester=kwargs.get('semester'),
            year_level=team.year_level, event_name__iexact=kwargs.get('event_name', '')).first()
        files = config.deliverables.all() if config else []
    timings = {d.deliverable_id: {'requirement_timing': 'defense', 'deadline_hours_before': d.deadline_hours_before}
               for d in files if d.deliverable_type == 'pre' and d.requirement_timing == 'defense'}
    return DefenseSchedule.objects.create(legacy_deliverable_policy={'timings': timings, 'waived_ids': []}, **kwargs)
