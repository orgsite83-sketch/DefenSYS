"""Real semester/recovery fixtures run exclusively in Django's test database."""
from unittest.mock import patch
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import (StudentTeam, TeamMembership, TeamTermParticipation,
                                 StudentCapstoneParticipation)
from student_teams.services import stage_progression_blocker, mark_stage_result
from student_teams.capstone_lifecycle import requirements_for
from user_management.academic_records.models import StudentAcademicRecord
from .models import SchoolYear, Semester, SemesterTransitionLog


class CapstoneTransitionTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='transition-admin', role='admin')
        self.client.force_authenticate(self.admin)
        years = [SchoolYear.objects.create(label=label) for label in ('2026-2027', '2027-2028', '2028-2029')]
        self.intake = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=years[0], label=Semester.SECOND, is_active=True,
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        self.normal = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=years[1], label=Semester.FIRST,
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        self.extension = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=years[1], label=Semester.SECOND,
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        self.last = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=years[2], label=Semester.FIRST,
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        self.expired = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=years[2], label=Semester.SECOND)
        DefenseStage.objects.update(is_active=False)
        self.first = DefenseStage.objects.create(label='Discovery workshop', display_order=1)
        self.second = DefenseStage.objects.create(label='Product review', display_order=2)
        for stage in (self.first, self.second):
            stage.deliverables.create(deliverable_id='PRE', label='Stage paper',
                deliverable_type='pre', required=True)
        self.team = self.make_team('Cedar')
        self.enroll(self.team, self.normal)

    def make_team(self, name, semester=None):
        leader = get_user_model().objects.create_user(username=f'leader-{name}', role='student')
        team = StudentTeam.objects.create(name=name, project_title=f'{name} project', leader=leader,
            semester=semester or self.intake, level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', capstone_phase=StudentTeam.PHASE_ACTIVE)
        TeamMembership.objects.create(team=team, student=leader, is_leader=True)
        return team

    def enroll(self, team, term):
        StudentAcademicRecord.objects.get_or_create(student=team.leader, semester=term,
            defaults={'year_level': '4th Year', 'section': 'BSIT-4A'})

    def assess(self, team, stage, verdict='approved', term=None, status='published'):
        from repository.deliverables.models import DeliverableSubmission
        DeliverableSubmission.objects.get_or_create(team=team, stage_label=stage.label,
            deliverable_id='PRE', defaults={'label': 'Stage paper', 'deliverable_type': 'pre',
                'file_name': 'stage-paper.pdf', 'status': DeliverableSubmission.STATUS_ACCEPTED})
        grade = TeamGrade(team=team, semester=term or team.semester, defense_stage=stage,
            scope='capstone', verdict=verdict, status=status, panel_score=85, adviser_score=85, peer_score=85)
        grade.save(clean=False)
        return grade

    def preview(self, target):
        response = self.client.get(f'/api/academic-periods/semesters/{target.pk}/transition-preview/')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def activate(self, target, **data):
        preview = self.preview(target)
        return self.client.post(f'/api/academic-periods/semesters/{target.pk}/activate/',
            {'preview_revision': preview.get('preview_revision', ''), **data}, format='json')

    def enter_normal(self):
        self.assess(self.team, self.first)
        response = self.activate(self.normal)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()



    def test_preview_is_read_only_and_covers_outgoing_teams(self):
        before = (TeamTermParticipation.objects.count(), StudentCapstoneParticipation.objects.count())
        preview = self.preview(self.normal)
        self.assertEqual(preview['capstone_review']['total'], 1)
        self.assertEqual(before, (TeamTermParticipation.objects.count(), StudentCapstoneParticipation.objects.count()))
        self.team.refresh_from_db()
        self.assertEqual(self.team.semester, self.intake)

    def test_normal_continuation_preserves_prerequisite_and_source_term(self):
        self.enter_normal()
        self.assertEqual(self.team.semester, self.normal)
        self.assertEqual(self.team.project_version, 1)
        self.assertEqual(stage_progression_blocker(self.team, self.second), '')
        old = self.team.term_participations.get(semester=self.intake)
        self.assertEqual(old.outcome, 'open')
        self.assertIsNotNone(old.closed_at)
        self.assertEqual(self.team.grade_records.get(defense_stage=self.first).semester, self.intake)

    def test_completion_goes_to_history_and_does_not_continue(self):
        self.enter_normal()
        self.assess(self.team, self.second)
        response = self.activate(self.extension)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(self.team.term_participations.filter(semester=self.extension).exists())
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'completed')
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.team.leader).state, 'completed')






    def test_unresolved_is_not_failed_even_when_forced(self):
        self.enter_normal()
        self.assess(self.team, self.second, 'for_redefense', status='pending')
        preview = self.preview(self.extension)
        self.assertEqual(preview['capstone_review']['teams'][0]['outcome'], 'needs_review')
        response = self.activate(self.extension, force=True, reason='Institutional term switch approved')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'needs_review')




    def test_historical_grade_sync_uses_source_term(self):
        self.enter_normal()
        grade = self.team.grade_records.get(defense_stage=self.first)
        progress = mark_stage_result(grade, user=self.admin)
        self.assertEqual(progress.semester, self.intake)
        self.assertFalse(self.team.stage_progress.filter(semester=self.normal, defense_stage=self.first).exists())

    def test_status_endpoint_cannot_bypass_review(self):
        self.enter_normal()
        response = self.client.patch(f'/api/academic-periods/semesters/{self.extension.pk}/', {'is_active': True}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(str(response.data['code']), 'stale_preview')

    def test_passing_verdict_with_required_files_missing_is_not_completion(self):
        from defense.stages.models import StageDeliverable
        self.enter_normal()
        StageDeliverable.objects.create(defense_stage=self.second, deliverable_id='PAPER',
            label='Required paper', required=True, deliverable_type='post')
        self.assess(self.team, self.second)
        row = self.preview(self.extension)['capstone_review']['teams'][0]
        self.assertEqual(row['outcome'], 'needs_review')
        self.assertFalse(row['can_include'])

    def test_unpublished_failed_verdict_remains_unresolved(self):
        self.enter_normal()
        self.assess(self.team, self.second, 'failed', status='pending')
        self.enroll(self.team, self.extension)
        row = self.preview(self.extension)['capstone_review']['teams'][0]
        self.assertEqual(row['outcome'], 'needs_review')
        self.assertFalse(row['can_include'])

    def test_cleared_flag_without_assessment_cannot_unlock_prerequisite(self):
        from student_teams.models import TeamStageProgress
        TeamStageProgress.objects.create(team=self.team, semester=self.intake, defense_stage=self.first, status='passed')
        self.assertTrue(stage_progression_blocker(self.team, self.second))







    def test_same_project_cannot_repeat_an_already_cleared_prior_term_stage(self):
        from student_teams.services import mark_stage_ready
        from grading.grades.services import GradeContextService
        from django.core.exceptions import ValidationError
        self.enter_normal()
        with self.assertRaises(ValidationError):
            mark_stage_ready(self.team, self.first, user=self.admin)
        grade, created = GradeContextService.get_or_create_unscheduled_team(self.team, stage_label=self.first.label)
        self.assertIsNone(grade)
        self.assertFalse(created)


    def test_stage_directory_uses_latest_cross_term_assessment(self):
        from repository.deliverables.services import current_stage_for_team
        self.enter_normal()
        placeholder = TeamGrade(team=self.team, semester=self.normal, scope='capstone', defense_stage=self.first)
        placeholder.save(clean=False)
        self.assertEqual(current_stage_for_team(self.team), self.second.label)
