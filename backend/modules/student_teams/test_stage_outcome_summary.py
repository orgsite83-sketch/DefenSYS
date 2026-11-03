"""Team triage keeps outcomes separate from next-attempt preparation."""
from copy import deepcopy

from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from repository.deliverables import test_submission_timing as fixtures
from student_teams.capstone_context import stage_context
from student_teams.serializers import StudentTeamSerializer


class StageOutcomeSummaryTests(APITestCase):
    setUp = fixtures.faculty_review_setup

    def grade(self, **overrides):
        values = dict(team=self.team, semester=self.semester,
            defense_stage=self.stage, verdict='for_redefense')
        return TeamGrade.objects.create(**{**values, **overrides})

    def test_outcome_does_not_replace_preparation_status_or_write_records(self):
        grade = self.grade()
        before = list(TeamGrade.all_objects.values())
        context = StudentTeamSerializer(self.team).data['defense_context']
        self.assertEqual(context['stage_verdict'], 'for_redefense')
        self.assertEqual(context['current_stage'], self.stage.label)
        self.assertNotEqual(context['stage_status'], 'for_redefense')
        self.assertEqual(list(TeamGrade.all_objects.values()), before)
        grade.verdict = ''  # A fresh scheduled hearing has no new outcome yet.
        grade.save(update_fields=['verdict'])
        self.assertEqual(stage_context(self.team)['stage_verdict'], '')

    def test_outcome_excludes_other_stages_terms_and_project_versions(self):
        from academic_period_management.models import Semester
        other_stage = DefenseStage.objects.create(label='Another checkpoint', display_order=2)
        self.grade(defense_stage=other_stage, verdict='approved')
        old_project = self.grade(verdict='failed')
        # TeamGrade.save captures the team's active version. Set up historical
        # evidence explicitly inside the isolated test database.
        TeamGrade.all_objects.filter(pk=old_project.pk).update(
            project_version=self.team.project_version + 1)
        other_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.grade(semester=other_term, verdict='approved_with_revisions')
        self.assertEqual(stage_context(self.team)['stage_verdict'], '')

    def test_historical_term_adapter_keeps_its_own_outcome(self):
        from academic_period_management.models import Semester
        self.grade(verdict='approved')
        earlier_team = deepcopy(self.team)
        other_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.grade(semester=other_term, verdict='failed')
        self.team.semester = other_term
        self.team.save(update_fields=['semester'])
        self.assertEqual(stage_context(earlier_team)['stage_verdict'], 'approved')
