import json
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.exceptions import ValidationError
from django.conf import settings
from rest_framework.test import APITestCase
from student_teams.models import TeamStageProgress

from . import tests as fixtures
from .models import PeerEvaluationSubmission, TeamGrade
from .peer_cleanup import preview_cleanup, remove_unscheduled_peer_grades
from .services import GradeContextService


class PrematurePeerCleanupTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric

    def setUp(self):
        fixtures.GradeCenterApiTests.setUp(self)
        self.grade = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)[0]
        self.capstone_schedule.delete()
        self.grade.refresh_from_db()
        self.capstone_team.ready_for_stage = None
        self.capstone_team.save(update_fields=['ready_for_stage'])
        TeamStageProgress.objects.filter(team=self.capstone_team, defense_stage=self.stage).delete()
        self.grade.peer_score = Decimal('80')
        self.grade.save()
        PeerEvaluationSubmission.objects.create(team_grade=self.grade, evaluator=self.student,
            evaluatee=self.second_student, total_score=4, max_score=5, breakdown=[])

    def apply(self, path, ids=None):
        return remove_unscheduled_peer_grades(semester_id=self.semester.pk,
            stage_label=self.stage.label, grade_ids=ids or [self.grade.pk],
            backup_path=path, reason='User requested removal of premature peer evaluations.')

    def test_preview_does_not_mutate_and_cleanup_backs_up_exact_records(self):
        protected = GradeContextService.get_or_create_for_schedule(self.pit_schedule)[0]
        preview = preview_cleanup(self.semester.pk, self.stage.label)
        self.assertEqual([row['grade_id'] for row in preview], [self.grade.pk])
        self.assertTrue(PeerEvaluationSubmission.objects.filter(team_grade=self.grade).exists())
        with TemporaryDirectory(dir=Path(settings.BASE_DIR).parent / '.tmp') as directory:
            path = Path(directory) / 'backup.json'
            result = self.apply(path)
            backup = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(result['removed_grades'], 1)
            self.assertEqual(result['removed_peer_submissions'], 1)
            self.assertEqual(result['removed_student_summaries'], 2)
            self.assertEqual(backup['grade_ids'], [self.grade.pk])
            self.assertEqual(len(backup['objects']), 4)
        self.assertFalse(TeamGrade.objects.filter(pk=self.grade.pk).exists())
        self.assertTrue(TeamGrade.objects.filter(pk=protected.pk).exists())

    def test_cleanup_rejects_non_peer_scores_and_endorsed_teams(self):
        with TemporaryDirectory(dir=Path(settings.BASE_DIR).parent / '.tmp') as directory:
            path = Path(directory) / 'backup.json'
            self.grade.adviser_score = Decimal('70')
            self.grade.save()
            with self.assertRaises(ValidationError):
                self.apply(path)
            self.assertFalse(path.exists())
            self.grade.adviser_score = None
            self.grade.save()
            self.capstone_team.ready_for_stage = self.stage.label
            self.capstone_team.save(update_fields=['ready_for_stage'])
            with self.assertRaises(ValidationError):
                self.apply(path)
            self.assertFalse(path.exists())

    def test_cleanup_refuses_changed_ids_and_existing_backup(self):
        with TemporaryDirectory(dir=Path(settings.BASE_DIR).parent / '.tmp') as directory:
            path = Path(directory) / 'backup.json'
            with self.assertRaises(ValidationError):
                self.apply(path, [self.grade.pk + 999])
            path.write_text('Existing recovery copy', encoding='utf-8')
            with self.assertRaises(FileExistsError):
                self.apply(path)
            self.assertEqual(path.read_text(encoding='utf-8'), 'Existing recovery copy')
            self.assertTrue(TeamGrade.objects.filter(pk=self.grade.pk).exists())
