from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.audit import filter_audit_logs
from authentication_access_control.models import SystemAuditLog
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam, TeamMembership, TeamStageProgress


class StageFileAccessTests(APITestCase):
    def setUp(self):
        media = TemporaryDirectory(prefix='defensys-stage-access-test-')
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name)
        settings.enable()
        self.addCleanup(settings.disable)
        User = get_user_model()
        self.admin = User.objects.create_user(username='access-admin', role='admin')
        self.student = User.objects.create_user(username='access-student', role='student')
        self.pit_lead = User.objects.create_user(username='access-pit-lead', role='faculty', is_pit_lead=True, pit_lead_year='3rd Year')
        school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=school_year, label=Semester.SECOND, is_active=True)
        self.old_semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST)
        self.stage = DefenseStage.objects.get(label='Concept Proposal')
        StageDeliverable.objects.filter(defense_stage=self.stage).delete()
        for pk, kind in [('D1', 'pre'), ('D2', 'pre'), ('FINAL', 'post')]:
            StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id=pk, label=pk, deliverable_type=kind, required=True)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester, is_officially_complete=True)
        self.team = self.make_team('Capstone A', '3rd Year', StudentTeam.LEVEL_3_CAPSTONE)
        self.second_team = self.make_team('Capstone B', '3rd Year', StudentTeam.LEVEL_3_CAPSTONE)
        self.old_team = self.make_team('Historical Capstone', '4th Year', StudentTeam.LEVEL_4_CAPSTONE, self.old_semester)
        self.pit_team = self.make_team('PIT 3', '3rd Year', StudentTeam.LEVEL_3_PIT)
        self.other_pit = self.make_team('PIT 2', '2nd Year', StudentTeam.LEVEL_2_PIT)
        TeamMembership.objects.create(team=self.team, student=self.student)
        for year in ('2nd Year', '3rd Year'):
            config = PitEventGradingConfig.objects.create(semester=self.semester, event_name=f'{year} PIT Showcase', is_officially_complete=True)
            for pk in ('P1', 'P2'):
                PitEventDeliverable.objects.create(pit_event_config=config, deliverable_id=pk, label=pk, deliverable_type='pre')
        self.approved = DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='D1', label='D1', deliverable_type='pre', status='accepted', file_name='wrong.pdf')
        self.second_approved = DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='D2', label='D2', deliverable_type='pre', status='accepted', file_name='other.pdf')
        self.final = DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='FINAL', label='FINAL', deliverable_type='post', status='accepted', file_name='final.pdf')
        self.grade = TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            stage_label=self.stage.label, status='published', verdict='approved', final_grade=85,
            panel_score=85, adviser_score=85, peer_score=85)
        self.progress, _ = TeamStageProgress.objects.update_or_create(team=self.team, semester=self.semester,
            defense_stage=self.stage, defaults={'status': TeamStageProgress.STATUS_PASSED})
        self.client.force_authenticate(self.admin)

    def make_team(self, name, year, level, semester=None):
        return StudentTeam.objects.create(name=name, year_level=year, level=level,
            semester=semester or self.semester, leader=self.student, project_title=name)

    def change(self, **changes):
        return self.client.post('/api/repository/deliverables/unlock/', {
            'scope': 'global', 'program_scope': 'capstone', 'stage_label': self.stage.label,
            'unlock_type': 'pre', 'target_state': True,
            'reason': 'Allow the team to correct its uploaded file.', **changes,
        }, format='json')

    def snapshot(self, **changes):
        response = self.client.get('/api/repository/deliverables/stage-access/', {
            'scope': 'global', 'program_scope': 'capstone', **changes,
        })
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def upload(self, deliverable_id='D1'):
        return self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': deliverable_id, 'file_name': 'correct.pdf',
            'file': SimpleUploadedFile('correct.pdf', b'%PDF-1.4\ncorrected', content_type='application/pdf'),
        }, format='multipart')

    def test_program_changes_are_limited_to_active_semester_and_track(self):
        response = self.change()
        self.assertEqual(response.status_code, 200, response.data)
        for team in (self.team, self.second_team):
            team.refresh_from_db()
            self.assertIn(f'{self.stage.label}:pre', team.unlocked_stages)
        for team in (self.old_team, self.pit_team, self.other_pit):
            team.refresh_from_db()
            self.assertEqual(team.unlocked_stages, [])
        self.grade.refresh_from_db()
        self.progress.refresh_from_db()
        self.assertEqual(self.grade.status, 'published')
        self.assertEqual(self.grade.final_grade, 85)
        self.assertEqual(self.progress.status, TeamStageProgress.STATUS_PASSED)
        self.approved.refresh_from_db()
        self.assertEqual(self.approved.status, 'accepted')
        self.assertFalse(self.approved.file_replacement_unlocked)

    def test_lock_really_blocks_naturally_open_post_uploads_and_persists(self):
        initial = next(row for row in self.snapshot()['stages'] if row['stage_label'] == self.stage.label)
        self.assertTrue(initial['post']['unlocked'])
        response = self.change(unlock_type='post', target_state=False)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['unlocked'])
        repeated = next(row for row in self.snapshot()['stages'] if row['stage_label'] == self.stage.label)
        self.assertFalse(repeated['post']['unlocked'])
        self.final.status = 'pending'
        self.final.save(update_fields=['status'])
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload('FINAL').status_code, 400)
        payload = self.client.get('/api/repository/deliverables/', {'stage_label': self.stage.label})
        final = next(row for row in payload.data['teams'][0]['selected_stage']['deliverables'] if row['id'] == 'FINAL')
        self.assertFalse(final['can_upload'])

    def test_snapshot_uses_upload_rules_for_redefense(self):
        self.grade.verdict = TeamGrade.VERDICT_FOR_REDEFENSE
        self.grade.save()
        row = next(item for item in self.snapshot()['stages'] if item['stage_label'] == self.stage.label)
        self.assertTrue(row['pre']['unlocked'])
        self.assertEqual(row['pre']['allowed_count'], 1)
        self.assertTrue(row['pre']['mixed'])
        self.assertEqual(row['post']['allowed_count'], 1)
        self.assertTrue(row['post']['mixed'])
        self.assertEqual(self.change(target_state=False).status_code, 200)
        row = next(item for item in self.snapshot()['stages'] if item['stage_label'] == self.stage.label)
        self.assertFalse(row['pre']['unlocked'])

    def test_partial_lock_preserves_other_half_of_legacy_all_grant(self):
        self.team.unlocked_stages = [self.stage.label]
        self.team.save(update_fields=['unlocked_stages'])
        response = self.change(scope='team', team_id=self.team.pk, target_state=False)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertIn(f'{self.stage.label}:post', self.team.unlocked_stages)
        self.assertIn(f'{self.stage.label}:pre:locked', self.team.unlocked_stages)
        self.assertNotIn(self.stage.label, self.team.unlocked_stages)

    def test_individual_unlock_uses_choice_b_without_unlocking_other_files(self):
        response = self.change(scope='team', team_id=self.team.pk, deliverable_id='D1')
        self.assertEqual(response.status_code, 200, response.data)
        self.approved.refresh_from_db()
        self.second_approved.refresh_from_db()
        self.assertTrue(self.approved.file_replacement_unlocked)
        self.assertFalse(self.second_approved.file_replacement_unlocked)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload('D2').status_code, 400)
        self.assertEqual(self.upload().status_code, 200)
        self.approved.refresh_from_db()
        self.assertEqual(self.approved.status, 'accepted')
        self.assertFalse(self.approved.file_replacement_unlocked)
        self.assertEqual(self.upload().status_code, 400)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.change(scope='team', team_id=self.team.pk, deliverable_id='D1').status_code, 200)
        self.approved.refresh_from_db()
        self.assertTrue(self.approved.file_replacement_unlocked)

    def test_specific_deliverable_can_open_inside_locked_file_group(self):
        self.assertEqual(self.change(unlock_type='all', target_state=False).status_code, 200)
        self.assertEqual(self.change(deliverable_id='D1').status_code, 200)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload().status_code, 200)
        self.assertEqual(self.upload('D2').status_code, 400)
        self.assertEqual(self.upload('FINAL').status_code, 400)

    def test_group_lock_revokes_prior_individual_replacement(self):
        self.assertEqual(self.change(deliverable_id='D1').status_code, 200)
        self.assertEqual(self.change(unlock_type='all', target_state=False).status_code, 200)
        self.approved.refresh_from_db()
        self.assertFalse(self.approved.file_replacement_unlocked)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload().status_code, 400)

    def test_admin_can_manage_pit_event_and_individual_deliverable(self):
        response = self.change(program_scope='pit', stage_label='3rd Year PIT Showcase', deliverable_id='P1')
        self.assertEqual(response.status_code, 200, response.data)
        self.pit_team.refresh_from_db()
        self.other_pit.refresh_from_db()
        self.team.refresh_from_db()
        self.assertIn('3rd Year PIT Showcase:deliverable:P1', self.pit_team.unlocked_stages)
        self.assertEqual(self.other_pit.unlocked_stages, [])
        self.assertEqual(self.team.unlocked_stages, [])

    def test_pit_lead_can_unlock_approved_pre_only_in_assigned_year(self):
        submission = DeliverableSubmission.objects.create(team=self.pit_team, stage_label='3rd Year PIT Showcase',
            deliverable_id='P1', label='P1', deliverable_type='pre', status='accepted')
        self.client.force_authenticate(self.pit_lead)
        response = self.change(program_scope='pit', stage_label='3rd Year PIT Showcase', deliverable_id='P1')
        self.assertEqual(response.status_code, 200, response.data)
        submission.refresh_from_db()
        self.assertTrue(submission.file_replacement_unlocked)
        state = self.snapshot(program_scope='pit')
        self.assertEqual(state['year_level'], '3rd Year')
        self.assertFalse(state['can_choose_program'])
        self.assertNotIn('2nd Year PIT Showcase', [row['stage_label'] for row in state['stages']])
        for changes in ({'program_scope': 'capstone'}, {'program_scope': 'pit', 'year_level': '2nd Year'},
                        {'program_scope': 'pit', 'stage_label': '2nd Year PIT Showcase'}):
            self.assertIn(self.change(**changes).status_code, (400, 403))
        self.other_pit.refresh_from_db()
        self.assertEqual(self.other_pit.unlocked_stages, [])
        scoped = filter_audit_logs(SystemAuditLog.objects.all(), {'track': 'pit', 'year_level': '3rd Year'})
        self.assertTrue(scoped.filter(action='repository.stage_access_updated').exists())

    def test_access_changes_capture_actor_reason_and_diff(self):
        self.assertEqual(self.change(target_state=False).status_code, 200)
        events = filter_audit_logs(SystemAuditLog.objects.all(), {'track': 'capstone'})
        self.assertEqual(events.count(), 2)
        event = events.first()
        self.assertEqual(event.actor, self.admin)
        self.assertEqual(event.reason, 'Allow the team to correct its uploaded file.')
        self.assertNotEqual(event.old_values['unlocked_stages'], event.new_values['unlocked_stages'])
        self.assertFalse(event.new_values['upload_allowed'])

    def test_invalid_inputs_and_missing_reason_cannot_mutate_access(self):
        for changes in ({'reason': ''}, {'scope': 'bad'}, {'program_scope': 'bad'}, {'unlock_type': 'bad'},
                        {'target_state': 'bad'}, {'stage_label': 'Not configured'}, {'deliverable_id': 'Not configured'}):
            self.assertEqual(self.change(**changes).status_code, 400)
        self.assertFalse(SystemAuditLog.objects.exists())
        self.assertEqual(self.change(target_state='false').status_code, 200)
        self.team.refresh_from_db()
        self.assertIn(f'{self.stage.label}:pre:locked', self.team.unlocked_stages)

    def test_audit_failure_rolls_back_every_team(self):
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('test audit failure')):
            with self.assertLogs('authentication_access_control.audit', level='ERROR'):
                response = self.change()
        self.assertEqual(response.status_code, 500)
        for team in (self.team, self.second_team):
            team.refresh_from_db()
            self.assertEqual(team.unlocked_stages, [])

    def test_approved_post_file_keeps_archive_protection(self):
        self.assertEqual(self.change(deliverable_id='FINAL').status_code, 200)
        self.final.refresh_from_db()
        self.assertEqual(self.final.status, 'accepted')
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload('FINAL').status_code, 400)

    def test_students_cannot_read_or_change_program_access(self):
        self.client.force_authenticate(self.student)
        self.assertEqual(self.change().status_code, 403)
        response = self.client.get('/api/repository/deliverables/stage-access/', {'scope': 'global'})
        self.assertEqual(response.status_code, 403)
