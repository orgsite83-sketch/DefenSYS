"""Candidate filtering must retain all paths through the canonical readiness check."""
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from .models import StudentTeam, TeamRecoveryAuthorization, TeamStageProgress
from .services import get_ready_teams, is_stage_ready, stage_readiness_candidates, mark_stage_ready


class ReadinessCandidateTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.leader = get_user_model().objects.create_user(username='candidate-student', role='student')
        cls.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2046-2047'),
            label=Semester.FIRST, is_active=True,
        )
        DefenseStage.objects.all().delete()
        cls.stage = DefenseStage.objects.create(
            label='Candidate Defense', code='candidate-defense', display_order=1,
            is_active=True, is_presentation_only=True,
        )

    def team(self, name, **values):
        return StudentTeam.objects.create(
            name=name, semester=self.semester, leader=self.leader,
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', **values,
        )

    def grade(self, team, verdict, **values):
        return TeamGrade.objects.create(
            team=team, semester=self.semester, defense_stage=self.stage,
            scope=TeamGrade.SCOPE_CAPSTONE, stage_label=self.stage.label,
            verdict=verdict, **values,
        )

    def authorization(self, team, action='retake', **values):
        return TeamRecoveryAuthorization.objects.create(
            team=team, semester=self.semester, defense_stage=self.stage,
            project_version=team.project_version, action=action, reason='Test recovery', **values,
        )

    def test_all_readiness_paths_match_unfiltered_checks(self):
        self.team('Never endorsed')
        ready = self.team('Endorsed')
        TeamStageProgress.objects.create(
            team=ready, semester=self.semester, defense_stage=self.stage, status='ready',
        )
        scheduled = self.team('Scheduled progress without appointment')
        TeamStageProgress.objects.create(
            team=scheduled, semester=self.semester, defense_stage=self.stage, status='scheduled',
        )
        redefense = self.team('Redefense')
        self.grade(redefense, 'for_redefense')
        verification = self.team('Unverified redefense')
        self.grade(verification, 'for_redefense', redefense_verification_required=True)
        retake = self.team('Authorized failed attempt')
        self.grade(retake, 'failed')
        self.authorization(retake)
        self.assertFalse(is_stage_ready(retake, self.stage))
        mark_stage_ready(retake, self.stage)
        consumed = self.team('Consumed recovery')
        self.grade(consumed, 'failed')
        self.authorization(consumed, consumed_at=timezone.now())
        replacement = self.team('Replacement concept', project_version=2)
        self.authorization(replacement, action='new_concept', replacement_project_version=2)
        self.assertFalse(is_stage_ready(replacement, self.stage))
        mark_stage_ready(replacement, self.stage)
        old = self.team('Previous project endorsement', project_version=2)
        progress = TeamStageProgress.objects.create(
            team=old, semester=self.semester, defense_stage=self.stage, status='ready',
        )
        TeamStageProgress.all_objects.filter(pk=progress.pk).update(project_version=1)
        previous_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        wrong_term = self.team('Previous semester endorsement')
        TeamStageProgress.objects.create(
            team=wrong_term, semester=previous_term, defense_stage=self.stage, status='ready',
        )
        passed = self.team('Already passed')
        self.grade(passed, 'approved')

        expected = {team.pk for team in StudentTeam.objects.all() if is_stage_ready(team, self.stage)}
        self.assertEqual(expected, {ready.pk, scheduled.pk, redefense.pk, retake.pk, replacement.pk})
        self.assertEqual(set(get_ready_teams(self.semester, self.stage).values_list('pk', flat=True)), expected)
        candidates = set(stage_readiness_candidates(StudentTeam.objects.all()).values_list('pk', flat=True))
        self.assertTrue(expected.issubset(candidates))
        self.assertNotIn(old.pk, candidates)
        self.assertNotIn(wrong_term.pk, candidates)

    def test_assessed_schedules_remain_ineligible_without_status_writes(self):
        team = self.team('Assessed active schedule')
        schedule = DefenseSchedule.objects.create(
            team=team, semester=self.semester, defense_stage=self.stage,
            scope='capstone', status='scheduled', scheduled_date='2046-10-01', start_time='08:00', room='Room 1',
        )
        self.grade(team, 'failed', schedule=schedule)
        self.assertIn(team, stage_readiness_candidates(StudentTeam.objects.all(), self.stage))
        self.assertFalse(get_ready_teams(self.semester, self.stage).exists())
        schedule.refresh_from_db()
        self.assertEqual(schedule.status, DefenseSchedule.STATUS_SCHEDULED)

    def test_prerequisite_stages_still_block_later_endorsements(self):
        later = DefenseStage.objects.create(label='Later Defense', code='later-defense', display_order=2)
        team = self.team('Missing prerequisite')
        TeamStageProgress.objects.create(
            team=team, semester=self.semester, defense_stage=later, status='ready',
        )
        self.assertIn(team, stage_readiness_candidates(StudentTeam.objects.all(), later))
        self.assertFalse(get_ready_teams(self.semester, later).exists())
