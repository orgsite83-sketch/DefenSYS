"""Real semester/recovery fixtures run exclusively in Django's test database."""
from unittest.mock import patch
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import (StudentTeam, TeamMembership, TeamTermParticipation,
                                 TeamRecoveryAuthorization, CapstoneJourney)
from student_teams.services import stage_progression_blocker, mark_stage_result
from student_teams.capstone_lifecycle import EXTENSION_POLICY, requirements_for
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
        self.first = DefenseStage.objects.create(label='Discovery workshop', display_order=1, is_presentation_only=True)
        self.second = DefenseStage.objects.create(label='Product review', display_order=2, is_presentation_only=True)
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

    def fail_normal(self):
        self.enter_normal()
        grade = self.assess(self.team, self.second, 'failed')
        self.enroll(self.team, self.extension)
        return grade

    def decision(self, **values):
        return {'team_id': self.team.pk, 'include': True, 'project_choice': 'continue', **values}

    def test_preview_is_read_only_and_covers_outgoing_teams(self):
        before = (TeamTermParticipation.objects.count(), CapstoneJourney.objects.count())
        preview = self.preview(self.normal)
        self.assertEqual(preview['capstone_review']['total'], 1)
        self.assertEqual(before, (TeamTermParticipation.objects.count(), CapstoneJourney.objects.count()))
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
        self.assertEqual(CapstoneJourney.objects.get(team=self.team).completed_project_version, 1)

    def test_failed_continuation_joins_fresh_batch_and_retains_failed_history(self):
        source = self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision()], reason='Approved extension review', request_id='return-cedar')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.capstone_phase, StudentTeam.PHASE_EXTENDED)
        self.assertEqual(self.team.project_version, 1)
        recovery = TeamRecoveryAuthorization.objects.get(team=self.team)
        self.assertEqual(recovery.source_grade, source)
        self.assertEqual(recovery.semester, self.extension)
        self.assertEqual(stage_progression_blocker(self.team, self.second), '')
        fresh = self.make_team('Fresh', self.extension)
        active = self.client.get('/api/teams/?scope=active&level=Capstone')
        self.assertEqual(active.status_code, 200, active.data)
        self.assertEqual({r['id'] for r in active.data['teams']}, {self.team.pk, fresh.pk})
        history = self.client.get('/api/teams/?scope=history&level=Capstone')
        old = next(row for row in history.data['teams'] if row['id'] == self.team.pk and row['semester_id'] == self.normal.pk)
        self.assertEqual(old['status'], 'Failed')
        self.assertFalse(old['is_editable'])

    def test_replacement_is_versioned_and_retry_does_not_duplicate(self):
        source = self.fail_normal()
        preview = self.preview(self.extension)
        body = {'preview_revision': preview['preview_revision'], 'reason': 'New project authorized',
            'request_id': 'replacement-once', 'decisions': [self.decision(project_choice='new', project_title='Replacement title')]}
        url = f'/api/academic-periods/semesters/{self.extension.pk}/activate/'
        for _ in range(2):
            response = self.client.post(url, body, format='json')
            self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        source.refresh_from_db()
        self.assertEqual(self.team.project_version, 2)
        self.assertEqual(source.project_version, 1)
        self.assertEqual(source.verdict, 'failed')
        self.assertEqual(TeamRecoveryAuthorization.objects.filter(team=self.team).count(), 1)
        self.assertEqual(CapstoneJourney.objects.get(team=self.team).extension_end_year, '2028-2029')
        self.assertTrue(stage_progression_blocker(self.team, self.second))
        old = self.client.get(f'/api/teams/{self.team.pk}/?semester_id={self.normal.pk}')
        self.assertEqual(old.data['team']['project_title'], 'Cedar project')
        self.assertEqual(old.data['team']['project_version'], 1)

    def test_every_eligible_failed_team_needs_explicit_choice(self):
        self.fail_normal()
        response = self.activate(self.extension)
        self.assertEqual(response.status_code, 400)
        self.normal.refresh_from_db()
        self.assertTrue(self.normal.is_active)

    def test_excluded_failed_team_can_join_after_late_enrollment(self):
        self.fail_normal()
        StudentAcademicRecord.objects.filter(student=self.team.leader, semester=self.extension).delete()
        response = self.activate(self.extension)
        self.assertEqual(response.status_code, 200, response.data)
        self.enroll(self.team, self.extension)
        url = f'/api/academic-periods/semesters/{self.extension.pk}/returning-teams/'
        preview = self.client.get(url).data
        result = self.client.post(url, {'preview_revision': preview['preview_revision'],
            'reason': 'Enrollment verified', 'decisions': [self.decision()]}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.semester, self.extension)

    def test_stale_assessment_or_enrollment_rejects_confirmation(self):
        self.fail_normal()
        preview = self.preview(self.extension)
        StudentAcademicRecord.objects.filter(student=self.team.leader, semester=self.extension).delete()
        response = self.client.post(f'/api/academic-periods/semesters/{self.extension.pk}/activate/',
            {'preview_revision': preview['preview_revision'], 'decisions': [self.decision()], 'reason': 'Reviewed'}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(str(response.data['code']), 'stale_preview')

    def test_unresolved_is_not_failed_even_when_forced(self):
        self.enter_normal()
        self.assess(self.team, self.second, 'for_redefense', status='pending')
        preview = self.preview(self.extension)
        self.assertEqual(preview['capstone_review']['teams'][0]['outcome'], 'needs_review')
        response = self.activate(self.extension, force=True, reason='Institutional term switch approved')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(TeamRecoveryAuthorization.objects.filter(team=self.team).exists())
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'needs_review')

    def test_allowance_does_not_reset_and_expiry_blocks_continuation(self):
        self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision()], reason='Extension approved')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        # A new pending attempt has not yet passed; it can carry within the same window.
        self.assess(self.team, self.second, 'for_redefense', status='pending')
        self.enroll(self.team, self.last)
        response = self.activate(self.last, force=True, reason='Carry within original allowance')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assess(self.team, self.second, 'failed')
        self.enroll(self.team, self.expired)
        preview = self.preview(self.expired)
        row = preview['capstone_review']['teams'][0]
        self.assertFalse(row['can_include'])
        self.assertEqual(row['destination'], 'institutional_review')
        self.assertIn('2028-2029', row['extension_deadline'])

    def test_atomic_failure_leaves_semester_and_team_unchanged(self):
        self.fail_normal()
        with patch('student_teams.capstone_lifecycle.authorize_recovery', side_effect=RuntimeError('fixture failure')):
            with self.assertRaises(RuntimeError):
                self.activate(self.extension, decisions=[self.decision()], reason='Reviewed')
        self.normal.refresh_from_db()
        self.team.refresh_from_db()
        self.assertTrue(self.normal.is_active)
        self.assertEqual(self.team.semester, self.normal)
        self.assertFalse(self.team.term_participations.filter(semester=self.extension).exists())

    def test_stage_names_and_fresh_batch_additions_do_not_change_extended_requirements(self):
        self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision()], reason='Reviewed')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        added = DefenseStage.objects.create(label='New batch workshop', display_order=3, is_presentation_only=True)
        self.assertNotIn(added.pk, {r['id'] for r in requirements_for(self.team)})
        self.first.label = 'Renamed discovery'
        self.first.save()
        self.assertEqual(stage_progression_blocker(self.team, self.second), '')

    def test_historical_grade_sync_uses_source_term(self):
        self.enter_normal()
        grade = self.team.grade_records.get(defense_stage=self.first)
        progress = mark_stage_result(grade, user=self.admin)
        self.assertEqual(progress.semester, self.intake)
        self.assertFalse(self.team.stage_progress.filter(semester=self.normal, defense_stage=self.first).exists())

    def test_status_endpoint_cannot_bypass_review(self):
        self.fail_normal()
        response = self.client.patch(f'/api/academic-periods/semesters/{self.extension.pk}/', {'is_active': True}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(str(response.data['code']), 'stale_preview')

    def test_passing_verdict_with_required_files_missing_is_not_completion(self):
        from defense.stages.models import StageDeliverable
        self.enter_normal()
        self.second.is_presentation_only = False
        self.second.save()
        StageDeliverable.objects.create(defense_stage=self.second, deliverable_id='PAPER',
            label='Required paper', required=True, deliverable_type='post')
        self.assess(self.team, self.second)
        row = self.preview(self.extension)['capstone_review']['teams'][0]
        self.assertEqual(row['outcome'], 'needs_review')
        self.assertFalse(row['can_include'])

    def test_unpublished_failed_verdict_does_not_grant_extension(self):
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

    def test_unused_recovery_carries_within_allowance_without_another_project_choice(self):
        self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision()], reason='Initial extension authorized')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.enroll(self.team, self.last)
        row = self.preview(self.last)['capstone_review']['teams'][0]
        self.assertTrue(row['can_include'])
        self.assertFalse(row['requires_project_choice'])
        response = self.activate(self.last)
        self.assertEqual(response.status_code, 200, response.data)
        current = TeamRecoveryAuthorization.objects.get(team=self.team, semester=self.last)
        self.assertEqual(current.action, 'retake')
        self.assertEqual(current.project_version, 1)
        self.assertTrue(TeamRecoveryAuthorization.objects.filter(team=self.team, semester=self.extension, consumed_at__isnull=False).exists())

    def test_late_return_retry_does_not_duplicate_authorization(self):
        self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision(include=False)])
        self.assertEqual(response.status_code, 200, response.data)
        url = f'/api/academic-periods/semesters/{self.extension.pk}/returning-teams/'
        body = {'preview_revision': self.client.get(url).data['preview_revision'], 'request_id': 'late-retry',
            'reason': 'Enrollment confirmed', 'decisions': [self.decision()]}
        for _ in range(2):
            result = self.client.post(url, body, format='json')
            self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(TeamRecoveryAuthorization.objects.filter(team=self.team).count(), 1)

    def test_late_normal_enrollment_preserves_the_closed_source_record(self):
        from user_management.academic_records.rollover import advance_capstone_teams
        StudentAcademicRecord.objects.filter(student=self.team.leader, semester=self.normal).delete()
        self.assess(self.team, self.first)
        result = self.activate(self.normal)
        self.assertEqual(result.status_code, 200, result.data)
        old = self.team.term_participations.get(semester=self.intake)
        snapshot = old.snapshot
        self.enroll(self.team, self.normal)
        self.normal.refresh_from_db()
        updates = advance_capstone_teams(self.normal, {self.intake.pk: {self.team.leader_id}})
        self.assertEqual(updates, 1)
        old.refresh_from_db()
        self.assertEqual(old.snapshot, snapshot)
        self.team.refresh_from_db()
        self.assertEqual(self.team.semester, self.normal)

    def test_fresh_team_creation_cannot_reset_returning_identity(self):
        self.fail_normal()
        result = self.activate(self.extension, decisions=[self.decision(include=False)])
        self.assertEqual(result.status_code, 200, result.data)
        response = self.client.post('/api/teams/', {'name': 'Reset attempt',
            'project_title': 'Different project', 'level': StudentTeam.LEVEL_4_CAPSTONE,
            'leader_id': self.team.leader_id, 'member_ids': [self.team.leader_id]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_existing_extended_without_original_cohort_never_gets_a_fresh_year(self):
        self.fail_normal()
        CapstoneJourney.objects.filter(team=self.team).delete()
        self.team.capstone_phase = StudentTeam.PHASE_EXTENDED
        self.team.save()
        row = self.preview(self.extension)['capstone_review']['teams'][0]
        self.assertFalse(row['can_include'])
        self.assertEqual(row['extension_deadline'], '')

    def test_source_roster_report_keeps_old_project_year_and_period(self):
        self.fail_normal()
        result = self.activate(self.extension, decisions=[self.decision(project_choice='new', project_title='New project')], reason='Reviewed replacement')
        self.assertEqual(result.status_code, 200, result.data)
        response = self.client.get('/api/reports/team-roster/', {'semester_id': self.intake.pk,
            'year_level': '3rd Year', 'scope': 'capstone', 'export_format': 'json'})
        self.assertEqual(response.status_code, 200, response.data)
        row = response.data['rows'][0]
        self.assertEqual(row['project_title'], 'Cedar project')
        self.assertIn('3rd Year', row['section'])
        self.assertIn('2026-2027', row['period'])
        grades = self.client.get('/api/reports/semester-grades/', {'semester_id': self.intake.pk,
            'year_level': '3rd Year', 'scope': 'capstone', 'export_format': 'json'})
        self.assertEqual(grades.status_code, 200, grades.data)
        self.assertEqual(grades.data['rows'][0]['project_title'], 'Cedar project')

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

    def test_roster_edit_preserves_the_authoritative_extended_phase(self):
        self.fail_normal()
        response = self.activate(self.extension, decisions=[self.decision()], reason='Approved extension')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        response = self.client.patch(f'/api/teams/{self.team.pk}/', {
            'name': 'Cedar updated', 'project_title': self.team.project_title,
            'level': self.team.level, 'year_level': self.team.year_level, 'section': self.team.section,
            'leader_id': self.team.leader_id, 'member_ids': [self.team.leader_id],
            'capstone_phase': StudentTeam.PHASE_ACTIVE,
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.name, 'Cedar updated')
        self.assertEqual(self.team.capstone_phase, StudentTeam.PHASE_EXTENDED)

    def test_stage_directory_uses_latest_cross_term_assessment(self):
        from repository.deliverables.services import current_stage_for_team
        self.assess(self.team, self.first, 'failed')
        response = self.activate(self.normal)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assess(self.team, self.first)
        self.assertEqual(current_stage_for_team(self.team), self.second.label)
