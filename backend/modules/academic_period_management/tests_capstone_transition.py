"""Real semester/recovery fixtures run exclusively in Django's test database."""
from unittest.mock import patch
from django.contrib.auth import get_user_model
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import (StudentTeam, TeamMembership, TeamTermParticipation,
                                 StudentCapstoneParticipation, PITSectionRoster)
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

    def make_pit_teams(self, semester):
        teams = []
        for index, level in enumerate((StudentTeam.LEVEL_1_PIT,
                StudentTeam.LEVEL_2_PIT, StudentTeam.LEVEL_3_PIT), start=1):
            year = level.rsplit(' ', 1)[0]
            leader = get_user_model().objects.create_user(
                username=f'pit-{semester.pk}-{index}', role='student')
            team = StudentTeam.objects.create(name=f'PIT {index}', project_title=f'PIT project {index}',
                semester=semester, level=level, year_level=year, section=f'BSIT-{index}A', leader=leader)
            TeamMembership.objects.create(team=team, student=leader, is_leader=True)
            roster = PITSectionRoster.objects.create(semester=semester,
                year_level=year, section=team.section)
            roster.teams.add(team)
            teams.append(team)
        return teams

    def assert_pit_stays(self, teams, source, target):
        for team in teams:
            with self.subTest(level=team.level):
                team.refresh_from_db()
                self.assertEqual(team.semester_id, source.pk)
                self.assertEqual(team.project_title, f'PIT project {teams.index(team) + 1}')
                self.assertEqual(list(team.memberships.values_list('student_id', flat=True)), [team.leader_id])
                self.assertTrue(team.current_pit_rosters.filter(semester=source).exists())
                self.assertFalse(team.term_participations.exists())
        self.assertFalse(StudentTeam.objects.filter(semester=target, level__icontains='PIT').exists())
        self.assertFalse(PITSectionRoster.objects.filter(semester=target).exists())
        self.assertFalse(StudentCapstoneParticipation.objects.filter(
            student_id__in=[team.leader_id for team in teams]).exists())

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

    def test_mixed_semester_migrates_only_capstone_and_preserves_all_pit_rosters(self):
        pit_teams = self.make_pit_teams(self.intake)
        self.assess(self.team, self.first)
        before = (StudentTeam.objects.count(), TeamMembership.objects.count(), PITSectionRoster.objects.count())
        preview = self.preview(self.normal)
        self.assertEqual(preview['impact_counts']['active_teams'], 4)
        self.assertEqual(preview['impact_counts']['capstone_teams'], 1)
        self.assertEqual(preview['impact_counts']['pit_teams'], 3)
        self.assertEqual([row['team_id'] for row in preview['capstone_review']['teams']], [self.team.pk])
        notice = next(effect for effect in preview['effects'] if effect['key'] == 'pit_teams')
        self.assertIn('This semester has 3 PIT teams.', notice['message'])
        self.assertIn('PIT starts fresh next semester', notice['message'])
        self.assertNotIn('route', notice)
        self.assertFalse(any(issue['key'] in ('active_teams', 'pit_teams') for issue in preview['issues']))
        response = self.activate(self.normal)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['transition_preview']['applied_team_ids'], [self.team.pk])
        self.assertEqual(before, (StudentTeam.objects.count(), TeamMembership.objects.count(), PITSectionRoster.objects.count()))
        self.assert_pit_stays(pit_teams, self.intake, self.normal)

    def test_enabled_capstone_switches_need_no_manual_closure_and_preserve_grading_settings(self):
        self.assess(self.team, self.first)
        self.intake.capstone_peer_evaluation_enabled = True
        self.intake.capstone_adviser_grading_enabled = True
        self.intake.save(update_fields=['capstone_peer_evaluation_enabled', 'capstone_adviser_grading_enabled'])
        grade_before = TeamGrade.all_objects.filter(team=self.team).values().get()
        preview = self.preview(self.normal)
        self.assertTrue(preview['can_switch'], preview['blocking_reasons'])
        self.assertEqual(preview['issues'], [])
        self.assertIn('capstone_evaluation_closure', [effect['key'] for effect in preview['effects']])
        self.intake.refresh_from_db()
        self.assertTrue(self.intake.is_active)
        payload = {'preview_revision': preview['preview_revision'], 'request_id': 'automatic-evaluation-closure'}
        with patch('realtime.broadcast.notify_capstone_evaluation_flags') as notify:
            with self.captureOnCommitCallbacks(execute=True):
                response = self.client.post(f'/api/academic-periods/semesters/{self.normal.pk}/activate/',
                    payload, format='json')
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual([call.args[0].pk for call in notify.call_args_list], [self.intake.pk, self.normal.pk])
            retry = self.client.post(f'/api/academic-periods/semesters/{self.normal.pk}/activate/', payload, format='json')
            self.assertEqual(retry.status_code, 200, retry.data)
            self.assertEqual(notify.call_count, 2)
        self.intake.refresh_from_db()
        self.normal.refresh_from_db()
        self.assertFalse(self.intake.is_active)
        self.assertTrue(self.intake.capstone_peer_evaluation_enabled)
        self.assertTrue(self.intake.capstone_adviser_grading_enabled)
        self.assertTrue(self.normal.is_active)
        self.assertFalse(self.normal.capstone_peer_evaluation_enabled)
        self.assertFalse(self.normal.capstone_adviser_grading_enabled)
        self.assertEqual(TeamGrade.all_objects.filter(team=self.team).values().get(), grade_before)
        self.assertEqual(SemesterTransitionLog.objects.count(), 1)

    def test_failed_switch_keeps_outgoing_semester_active_and_sends_no_refresh(self):
        self.assess(self.team, self.first)
        history_before = list(TeamTermParticipation.objects.order_by('pk').values())
        preview = self.preview(self.normal)
        with patch('realtime.broadcast.notify_capstone_evaluation_flags') as notify:
            with self.captureOnCommitCallbacks(execute=True), patch(
                    'academic_period_management.services.log_high_impact_action',
                    side_effect=ValidationError('Audit write failed.')):
                response = self.client.post(f'/api/academic-periods/semesters/{self.normal.pk}/activate/',
                    {'preview_revision': preview['preview_revision']}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
            notify.assert_not_called()
        self.intake.refresh_from_db()
        self.normal.refresh_from_db()
        self.team.refresh_from_db()
        self.assertTrue(self.intake.is_active)
        self.assertFalse(self.normal.is_active)
        self.assertEqual(self.team.semester_id, self.intake.pk)
        self.assertFalse(SemesterTransitionLog.objects.exists())
        self.assertEqual(list(TeamTermParticipation.objects.order_by('pk').values()), history_before)

    def test_pit_starts_fresh_in_both_regular_term_directions(self):
        self.team.delete()
        for source, target in ((self.intake, self.normal), (self.normal, self.extension)):
            with self.subTest(source=source.label):
                source.capstone_peer_evaluation_enabled = True
                source.capstone_adviser_grading_enabled = True
                source.save(update_fields=['capstone_peer_evaluation_enabled', 'capstone_adviser_grading_enabled'])
                pit_teams = self.make_pit_teams(source)
                preview = self.preview(target)
                self.assertEqual(preview['capstone_review']['total'], 0)
                self.assertEqual(preview['impact_counts']['capstone_teams'], 0)
                self.assertTrue(preview['can_switch'], preview['blocking_reasons'])
                response = self.activate(target)
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(response.data['transition_preview']['applied_team_ids'], [])
                self.assert_pit_stays(pit_teams, source, target)

    def test_pit_grading_blocks_closure_but_a_calendar_override_never_migrates_pit(self):
        from defense.scheduler.models import PitEventGradingConfig
        pit_teams = self.make_pit_teams(self.intake)
        self.assess(self.team, self.first)
        event = PitEventGradingConfig.objects.create(semester=self.intake,
            year_level='1st Year', event_name='Outgoing PIT expo', peer_grading_enabled=True)
        preview = self.preview(self.normal)
        self.assertEqual(preview['impact_counts']['pit_peer_grading_windows'], 1)
        self.assertFalse(preview['can_switch'])
        blocked = self.activate(self.normal)
        self.assertEqual(blocked.status_code, 400, blocked.data)
        response = self.activate(self.normal, force=True, reason='Approved calendar exception')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['transition_preview']['applied_team_ids'], [self.team.pk])
        event.refresh_from_db()
        self.assertEqual(event.semester_id, self.intake.pk)
        self.assertTrue(event.peer_grading_enabled)
        self.assertFalse(event.is_officially_complete)
        self.assert_pit_stays(pit_teams, self.intake, self.normal)

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
