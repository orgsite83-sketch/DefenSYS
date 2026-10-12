from io import StringIO

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.management import call_command
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from grading.grades.models import PanelistGradeSubmission
from . import tests as fixtures
from .models import DefenseSchedule, SchedulePanelist
from .panelist_evaluation import grading_unavailable_reason, verdict_unavailable_reason
from .serializers import DefenseScheduleWriteSerializer


class AdviserPanelConflictTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team
    create_scheduled_defense = fixtures.DefenseSchedulerApiTests.create_scheduled_defense

    def post(self, endpoint='', **changes):
        return self.client.post(f'/api/defense/schedules/{endpoint}',
            self.schedule_payload(**changes), format='json')

    def session(self, **changes):
        return {'key': 'session-1', 'scheduled_date': '2026-05-15',
            'start_time': '08:00', 'end_time': '10:00', 'slot_duration': 60,
            'room': 'Room 301', 'team_ids': [self.team.pk], **changes}

    def test_single_schedule_rejects_adviser_as_chair_or_member_without_role_grant(self):
        for chair in (self.adviser.pk, self.panelist.pk):
            with self.subTest(chair=chair):
                response = self.post(team_id=self.team.pk,
                    panelist_ids=[self.adviser.pk, self.panelist.pk], chair_panelist_id=chair)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('team adviser cannot', str(response.data['panelist_ids']))
                self.assertIn(self.team.name, str(response.data))
                self.assertFalse(DefenseSchedule.objects.exists())
        self.adviser.refresh_from_db()
        self.assertFalse(self.adviser.is_panelist)

    def test_manual_save_rechecks_adviser_changed_since_validation(self):
        from types import SimpleNamespace
        serializer = DefenseScheduleWriteSerializer(data=self.schedule_payload(team_id=self.team.pk),
            context={'request': SimpleNamespace(user=self.admin)})
        serializer.is_valid(raise_exception=True)
        self.team.adviser = self.panelist
        self.team.save(update_fields=['adviser'])
        from rest_framework.exceptions import ValidationError as ApiValidationError
        with self.assertRaises(ApiValidationError):
            serializer.save()
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_legacy_generation_and_confirmation_reject_adviser(self):
        for endpoint in ('generate-plan/', 'confirm-plan/'):
            changes = {'panelist_ids': [self.adviser.pk], 'chair_panelist_id': self.adviser.pk}
            if endpoint == 'confirm-plan/':
                changes['slots'] = [{'team_id': self.team.pk}]
            response = self.post(endpoint, **changes)
            self.assertEqual(response.status_code, 400, response.data)
            self.assertIn('team adviser cannot', str(response.data['slots']))
            self.assertFalse(DefenseSchedule.objects.exists())

    def test_session_override_rejects_adviser_as_chair_and_member(self):
        for chair in (self.adviser.pk, self.panelist.pk):
            session = self.session(panelist_ids=[self.adviser.pk, self.panelist.pk], chair_panelist_id=chair)
            for endpoint in ('generate-plan/', 'confirm-plan/'):
                changes = {'sessions': [session]}
                if endpoint == 'confirm-plan/':
                    changes['slots'] = [{'team_id': self.team.pk, 'session_key': 'session-1'}]
                response = self.post(endpoint, **changes)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('team adviser cannot', str(response.data['slots']))
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_confirmation_rechecks_adviser_after_preview(self):
        sessions = [self.session()]
        generated = self.post('generate-plan/', sessions=sessions)
        self.assertEqual(generated.status_code, 200, generated.data)
        self.team.adviser = self.panelist
        self.team.save(update_fields=['adviser'])
        response = self.post('confirm-plan/', sessions=sessions, slots=generated.data['slots'])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('team adviser cannot', str(response.data['slots']))
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_mixed_batch_conflict_is_atomic(self):
        other = self.create_ready_team()
        other.adviser = self.panelist
        other.save(update_fields=['adviser'])
        response = self.post('confirm-plan/', sessions=[self.session(team_ids=[self.team.pk, other.pk])],
            slots=[{'team_id': self.team.pk, 'session_key': 'session-1'},
                   {'team_id': other.pk, 'session_key': 'session-1'}])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(SystemAuditLog.objects.filter(action='schedule.create').exists())

    def test_adviser_can_panel_a_different_advisers_team(self):
        self.panelist.is_adviser = True
        self.panelist.save(update_fields=['is_adviser'])
        generated = self.post('generate-plan/', sessions=[self.session()])
        self.assertEqual(generated.status_code, 200, generated.data)
        confirmed = self.post('confirm-plan/', sessions=[self.session()], slots=generated.data['slots'])
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertTrue(DefenseSchedule.objects.get(team=self.team).panelists.filter(pk=self.panelist.pk).exists())

    def test_model_rejects_direct_conflicting_panel_assignment(self):
        schedule = self.create_scheduled_defense()
        with self.assertRaises(ValidationError):
            SchedulePanelist.objects.create(schedule=schedule, panelist=self.adviser)

    def test_operational_edit_rechecks_current_adviser_before_panel_change(self):
        from unittest.mock import patch
        from rest_framework.exceptions import ValidationError as ApiValidationError
        from student_teams.models import StudentTeam
        from .operations import execute_operation
        schedule = self.create_scheduled_defense()
        schedule.team = self.team
        incoming = get_user_model().objects.create_user(
            username='incoming-adviser', role='faculty', is_panelist=True, is_adviser=True)
        StudentTeam.objects.filter(pk=self.team.pk).update(adviser=incoming)
        with patch('defense.scheduler.operations.selection', return_value=[schedule]):
            with self.assertRaises(ApiValidationError) as rejected:
                execute_operation(self.admin, {
                    'action': 'update', 'reason': 'Update the defense panel.',
                    'expected_revisions': {str(schedule.pk): schedule.revision},
                    'changes': {'panelist_ids': [incoming.pk], 'chair_panelist_id': incoming.pk},
                })
        self.assertIn('team adviser cannot', str(rejected.exception.detail))
        self.assertFalse(schedule.panelists.filter(pk=incoming.pk).exists())

    def test_adviser_reassignment_cannot_create_open_panel_conflict(self):
        self.create_scheduled_defense()
        response = self.client.patch(f'/api/teams/{self.team.pk}/', {
            'name': self.team.name, 'project_title': self.team.project_title,
            'level': self.team.level, 'year_level': self.team.year_level,
            'leader_id': self.student.pk, 'member_ids': [self.student.pk],
            'adviser_id': self.panelist.pk,
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('active defense panel', str(response.data))
        self.team.refresh_from_db()
        self.assertEqual(self.team.adviser_id, self.adviser.pk)
        self.team.adviser = self.panelist
        with self.assertRaises(ValidationError):
            self.team.save(update_fields=['adviser'])

    def legacy_conflict(self):
        schedule = self.create_scheduled_defense()
        # Deliberately reproduce data created before roster validation existed.
        schedule.panel_assignments.update(is_chair=False)
        SchedulePanelist.objects.bulk_create([SchedulePanelist(
            schedule=schedule, panelist=self.adviser, order=2, is_chair=True)])
        return schedule

    def test_legacy_conflict_blocks_grading_drafts_and_verdict(self):
        schedule = self.legacy_conflict()
        self.adviser.is_panelist = True
        self.adviser.save(update_fields=['is_panelist'])
        self.assertIn('team adviser cannot', grading_unavailable_reason(schedule))
        self.assertIn('team adviser cannot', verdict_unavailable_reason(schedule, schedule.grade_records.first()))
        self.client.force_authenticate(self.adviser)
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk,
            'criteria_scores': fixtures.DefenseSchedulerApiTests.criteria_scores(self, 8),
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('team adviser cannot', str(response.data))
        self.assertFalse(PanelistGradeSubmission.objects.filter(schedule=schedule).exists())
        response = self.client.post('/api/defense/schedules/grade-draft/', {
            'schedule_id': schedule.pk, 'submissions': [{'criteria_scores': []}],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('team adviser cannot', str(response.data))

    def test_audited_repair_preserves_size_and_chair_and_dry_run_is_read_only(self):
        schedule = self.legacy_conflict()
        replacement = get_user_model().objects.create_user(
            username='replacement-panelist', role='faculty', is_panelist=True)
        before_count = schedule.panelists.count()
        before_audits = SystemAuditLog.objects.count()
        call_command('repair_adviser_panel_conflicts', schedule_ids=[schedule.pk],
            actor=self.admin.username, stdout=StringIO())
        self.assertTrue(schedule.panelists.filter(pk=self.adviser.pk).exists())
        self.assertEqual(SystemAuditLog.objects.count(), before_audits)
        call_command('repair_adviser_panel_conflicts', schedule_ids=[schedule.pk],
            actor=self.admin.username, apply=True, stdout=StringIO())
        self.assertEqual(schedule.panelists.count(), before_count)
        self.assertFalse(schedule.panelists.filter(pk=self.adviser.pk).exists())
        self.assertEqual(schedule.panel_assignments.get(is_chair=True).panelist_id, replacement.pk)
        self.assertTrue(SystemAuditLog.objects.filter(target_id=str(schedule.pk), action='schedule.operational_change').exists())

    def test_repaired_minutes_uses_current_panel_and_retains_former_comments(self):
        from io import BytesIO
        import pdfplumber
        from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
        from defense.minutes.pdf_generator import generate_minutes_pdf
        from defense.minutes.serializers import DefenseMinutesSerializer
        schedule = self.legacy_conflict()
        replacement = get_user_model().objects.create_user(username='new-chair',
            first_name='Ricardo', last_name='Fontanilla', role='faculty', is_panelist=True)
        minutes = DefenseMinutes.objects.create(schedule=schedule, team_name=self.team.name,
            project_title=self.team.project_title, adviser_name='Original Adviser',
            defense_stage_label=self.stage.label, defense_date=schedule.scheduled_date,
            defense_time=schedule.start_time, room=schedule.room, documenter_name='Documenter')
        previous = MinutesPanelistComment.objects.create(minutes=minutes, panelist=self.adviser,
            panelist_name_snapshot='Former Conflicting Chair', panelist_role_snapshot='Chair',
            comments='Former panel evidence retained for audit.')
        call_command('repair_adviser_panel_conflicts', schedule_ids=[schedule.pk],
            actor=self.admin.username, apply=True, stdout=StringIO())
        minutes = DefenseMinutes.objects.get(pk=minutes.pk)
        serialized = DefenseMinutesSerializer(minutes).data['panelist_comments']
        self.assertNotIn(self.adviser.pk, [row['panelist'] for row in serialized])
        self.assertIn(replacement.pk, [row['panelist'] for row in serialized])
        for minutes_status in ('draft', 'completed'):
            minutes.status = minutes_status
            with pdfplumber.open(BytesIO(generate_minutes_pdf(minutes, include_signatures=False, draft=True))) as pdf:
                content = '\n'.join(page.extract_text() for page in pdf.pages)
            self.assertIn('Ricardo Fontanilla (Chair)', content)
            self.assertNotIn('Former Conflicting Chair', content)
        self.assertTrue(MinutesPanelistComment.objects.filter(pk=previous.pk,
            comments='Former panel evidence retained for audit.').exists())
