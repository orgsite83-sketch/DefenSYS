import json
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
from grading.grades.models import GradeAttemptHistory, PanelistCriterionScore, PanelistGradeSubmission, TeamGrade
from . import tests as fixtures
from .models import DefenseSchedule, PanelistEvaluationDraft
from .panelist_evaluation import evaluation_context
from .services import DEMO_PANELIST_SETUP_ACTION


@override_settings(DEBUG=True)
class DemoPanelistSetupTests(APITestCase):
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    create_scheduled_defense = fixtures.DefenseSchedulerApiTests.create_scheduled_defense
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team

    def setUp(self):
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.target = get_user_model().objects.create_user(username='213', role='faculty',
            first_name='Florencia', last_name='Dela Torre', is_panelist=True)
        self.schedule = self.create_scheduled_defense()
        self.schedule.panel_assignments.filter(panelist=self.panelist).update(is_chair=True)
        self.minutes = DefenseMinutes.objects.create(schedule=self.schedule,
            team_name=self.team.name, project_title=self.team.project_title,
            adviser_name='Original Adviser', defense_stage_label=self.stage.label,
            defense_date=self.schedule.scheduled_date, defense_time=self.schedule.start_time,
            room=self.schedule.room, documenter_name='Documenter')
        self.comment = MinutesPanelistComment.objects.create(minutes=self.minutes,
            panelist=self.panelist, panelist_name_snapshot='Original Panelist',
            panelist_role_snapshot='Chair', comments='Keep these detailed comments.')

    def run_setup(self, **options):
        call_command('setup_demo_panelist', demo=True, source=self.panelist.username,
            replacement=self.target.username, actor=self.admin.username,
            schedule_ids=[self.schedule.pk], stdout=StringIO(), **options)

    def test_preview_and_production_or_signed_records_do_not_change_data(self):
        self.run_setup()
        self.assertFalse(self.schedule.panelists.filter(pk=self.target.pk).exists())
        self.assertFalse(SystemAuditLog.objects.filter(action=DEMO_PANELIST_SETUP_ACTION).exists())
        with override_settings(DEBUG=False), self.assertRaises(CommandError):
            self.run_setup()
        self.minutes.status = 'submitted'
        self.minutes.save(update_fields=['status'])
        with self.assertRaises(CommandError):
            self.run_setup()
        self.assertTrue(self.schedule.panelists.filter(pk=self.panelist.pk).exists())

    def test_completed_published_scores_comments_and_attempt_history_are_preserved(self):
        grade = TeamGrade.objects.create(schedule=self.schedule, team=self.team, semester=self.semester,
            defense_stage=self.stage, scope='capstone', verdict='approved', verdict_by=self.panelist)
        TeamGrade.all_objects.filter(pk=grade.pk).update(status='published', panel_score=85,
            adviser_score=88, peer_score=90, final_grade=87)
        DefenseSchedule.objects.filter(pk=self.schedule.pk).update(status='done')
        submission = PanelistGradeSubmission.objects.create(team_grade=grade, schedule=self.schedule,
            panelist=self.panelist, remarks='Keep this evaluation.')
        score = PanelistCriterionScore.objects.create(submission=submission, criterion=self.criterion,
            criterion_name_snapshot=self.criterion.name, score=8, max_score_snapshot=10)
        history = GradeAttemptHistory.objects.create(team_grade=grade, schedule=self.schedule,
            attempt_number=1, verdict='approved', verdict_by=self.panelist, panel_score=85)
        original_submission_time = submission.updated_at
        with TemporaryDirectory() as directory:
            backup = Path(directory) / 'before.json'
            self.run_setup(apply=True, backup=str(backup))
            archived = json.loads(backup.read_text(encoding='utf-8'))
            self.assertTrue(any(row['model'] == 'grading.panelistcriterionscore' and row['pk'] == score.pk for row in archived))
            # Retrying is idempotent and does not replace the saved backup.
            self.run_setup(apply=True, backup=str(backup))
        submission.refresh_from_db(); score.refresh_from_db(); grade.refresh_from_db()
        history.refresh_from_db(); self.comment.refresh_from_db(); self.schedule.refresh_from_db()
        self.assertEqual(submission.panelist_id, self.target.pk)
        self.assertEqual((submission.remarks, submission.updated_at), ('Keep this evaluation.', original_submission_time))
        self.assertEqual(score.score, 8)
        self.assertEqual((grade.status, grade.panel_score, grade.final_grade, grade.verdict), ('published', 85, 87, 'approved'))
        self.assertEqual((grade.verdict_by_id, history.verdict_by_id), (self.target.pk, self.target.pk))
        self.assertEqual(self.schedule.status, 'done')
        self.assertEqual(self.schedule.panel_assignments.get(is_chair=True).panelist_id, self.target.pk)
        self.assertEqual((self.comment.comments, self.comment.panelist_name_snapshot),
            ('Keep these detailed comments.', 'Florencia Dela Torre'))
        self.assertEqual(SystemAuditLog.objects.filter(action=DEMO_PANELIST_SETUP_ACTION).count(), 1)

    def test_unsent_draft_survives_identity_change_without_stale_context(self):
        draft = PanelistEvaluationDraft.objects.create(schedule=self.schedule, panelist=self.panelist,
            context_signature=evaluation_context(self.schedule), submissions=[{'criteria_scores': [{'score': 8}]}])
        with TemporaryDirectory() as directory:
            self.run_setup(apply=True, backup=str(Path(directory) / 'before.json'))
        draft.refresh_from_db(); self.schedule.refresh_from_db()
        self.assertEqual(draft.panelist_id, self.target.pk)
        self.assertEqual(draft.context_signature, evaluation_context(self.schedule))
        self.assertEqual(draft.submissions, [{'criteria_scores': [{'score': 8}]}])

    def test_temporary_repair_carries_original_comments_into_current_panel(self):
        temporary = get_user_model().objects.create_user(username='temporary-panel',
            role='faculty', is_panelist=True)
        self.schedule.panel_assignments.filter(panelist=self.panelist).update(panelist=temporary)
        placeholder = MinutesPanelistComment.objects.create(minutes=self.minutes,
            panelist=temporary, panelist_name_snapshot='Temporary Chair', comments='')
        with TemporaryDirectory() as directory:
            self.run_setup(apply=True, backup=str(Path(directory) / 'before.json'),
                temporary_source=temporary.username, temporary_schedule_ids=[self.schedule.pk])
        self.comment.refresh_from_db(); self.minutes.refresh_from_db()
        self.assertEqual(self.schedule.panel_assignments.get(is_chair=True).panelist_id, self.target.pk)
        current = self.minutes.current_panelist_comments
        self.assertEqual([row.pk for row in current], [self.comment.pk])
        self.assertEqual(current[0].comments, 'Keep these detailed comments.')
        self.assertTrue(MinutesPanelistComment.objects.filter(pk=placeholder.pk).exists())

    def test_demo_baseline_hides_old_badge_retains_history_and_shows_future_changes(self):
        def edit(room):
            self.schedule.refresh_from_db()
            return self.client.post('/api/defense/board/operations/', {
                'action': 'update', 'anchor_id': self.schedule.pk,
                'expected_revisions': {str(self.schedule.pk): self.schedule.revision},
                'reason': 'Change the room for this session.', 'changes': {'room': room},
            }, format='json')
        def visible_change():
            records = self.client.get('/api/defense/board/').data['schedules']
            return next(row['latest_change'] for row in records if row['id'] == self.schedule.pk)
        self.assertEqual(edit('Room 404').status_code, 200)
        self.assertIsNotNone(visible_change())
        with TemporaryDirectory() as directory:
            self.run_setup(apply=True, backup=str(Path(directory) / 'before.json'))
        self.assertIsNone(visible_change())
        history = self.client.get(f'/api/defense/board/operations/?history_for={self.schedule.pk}').data['history']
        self.assertEqual(len(history), 1)
        with override_settings(DEBUG=False):
            self.assertIsNotNone(visible_change())
        self.assertEqual(edit('Room 405').status_code, 200)
        self.assertIsNotNone(visible_change())

    def test_target_with_advisees_or_existing_evaluation_is_rejected(self):
        self.team.adviser = self.target
        self.team.save(update_fields=['adviser'])
        with self.assertRaisesMessage(CommandError, 'no assigned advisees'):
            self.run_setup()
        self.team.adviser = self.adviser
        self.team.save(update_fields=['adviser'])
        PanelistEvaluationDraft.objects.create(schedule=self.schedule, panelist=self.target,
            context_signature='existing', submissions=[])
        with self.assertRaisesMessage(CommandError, 'already has evaluation data'):
            self.run_setup()
        self.assertTrue(self.schedule.panelists.filter(pk=self.panelist.pk).exists())
