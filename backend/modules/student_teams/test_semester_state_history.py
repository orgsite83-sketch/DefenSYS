"""Real rollover/history regressions in Django's isolated test database."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.tests_capstone_transition import CapstoneTransitionTests as _Fixtures
from defense.configuration_locks import grade_configuration_lock
from defense.stages.models import DefenseStage, StageGradingConfig
from student_teams.models import TeamTermParticipation, TeamStageProgress
from student_teams.serializers import StudentTeamSerializer
from user_management.academic_records.models import StudentAcademicRecord
from unittest.mock import patch


class SemesterStateHistoryTests(APITestCase):
    setUp = _Fixtures.setUp
    make_team = _Fixtures.make_team
    enroll = _Fixtures.enroll
    assess = _Fixtures.assess
    preview = _Fixtures.preview
    activate = _Fixtures.activate

    def continue_team(self):
        self.assess(self.team, self.first)
        self.assess(self.team, self.second)
        response = self.activate(self.normal)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()

    def test_continuation_without_setup_never_falls_back_to_source_stage(self):
        self.continue_team()
        self.team.current_defense_stage = self.first.label
        self.team.save()
        data = StudentTeamSerializer(self.team).data
        self.assertIsNone(data['defense_context']['current_stage'])
        self.assertEqual(data['defense_context']['stage_status'], 'awaiting_stage_setup')
        self.assertEqual(data['deliverable_count'], 0)
        self.assertIsNone(data['defense_context']['concept_workflow'])
        grades = self.client.get('/api/grading/grades/', {'scope': 'capstone'})
        self.assertEqual(grades.data['capstone_stages'], [])

    def test_new_stage_and_completed_name_remain_independent_of_enrollment(self):
        self.continue_team()
        StudentAcademicRecord.objects.filter(semester=self.normal).delete()
        stage = DefenseStage.objects.create(label='Implementation review', display_order=3)
        data = StudentTeamSerializer(self.team).data
        self.assertEqual(data['defense_context']['current_stage'], stage.label)
        self.assertFalse(data['members'][0]['is_enrolled'])
        TeamStageProgress.objects.create(team=self.team, semester=self.normal,
            project_version=self.team.project_version, defense_stage=stage, status='passed')
        data = StudentTeamSerializer(self.team).data
        self.assertEqual(data['defense_context']['current_stage'], stage.label)
        self.assertEqual(data['defense_context']['stage_status'], 'passed')
        self.assertFalse(data['members'][0]['is_enrolled'])

    def test_admin_setup_actions_do_not_reopen_inherited_stages(self):
        for stage in (self.first, self.second):
            StageGradingConfig.objects.create(defense_stage=stage, semester=self.intake,
                is_officially_complete=True)
        self.continue_team()
        # An empty destination placeholder is not a new phase requirement.
        StageGradingConfig.objects.create(defense_stage=self.first, semester=self.normal)
        before = list(StageGradingConfig.objects.values())
        response = self.client.get('/api/dashboards/admin/')
        self.assertEqual(response.status_code, 200, response.data)
        actions = {item['id'] for item in response.data['action_items']}
        self.assertNotIn('stages_without_rubrics', actions)
        self.assertNotIn('stages_without_deliverables', actions)
        self.assertEqual(response.data['team_pipeline']['stage_distribution'], [])
        self.assertEqual(response.data['stats']['active_defense_stages'], 0)
        self.assertEqual(list(StageGradingConfig.objects.values()), before)

    def test_admin_setup_actions_keep_new_stages_after_continuation(self):
        self.continue_team()
        stage = DefenseStage.objects.create(label='Implementation review', display_order=3)
        response = self.client.get('/api/dashboards/admin/')
        self.assertEqual(response.status_code, 200, response.data)
        actions = {item['id']: item for item in response.data['action_items']}
        for key in ('stages_without_rubrics', 'stages_without_deliverables'):
            self.assertIn(stage.label, actions[key]['title'])
            self.assertNotIn(self.first.label, actions[key]['description'])
            self.assertNotIn(self.second.label, actions[key]['description'])
        self.assertEqual([item['label'] for item in response.data['team_pipeline']['stage_distribution']],
            [stage.label])

    def test_admin_setup_actions_still_include_reused_stages_for_a_new_intake(self):
        StageGradingConfig.objects.create(defense_stage=self.first, semester=self.intake,
            is_officially_complete=True)
        self.continue_team()
        self.make_team('New intake', self.extension)
        self.extension.is_active = True
        self.extension.save(update_fields=['is_active'])
        response = self.client.get('/api/dashboards/admin/')
        self.assertEqual(response.status_code, 200, response.data)
        item = next(item for item in response.data['action_items'] if item['id'] == 'stages_without_rubrics')
        self.assertIn(self.first.label, item['description'])
        self.assertIn(self.second.label, item['description'])

    def test_history_keeps_both_linked_terms_and_term_specific_enrollment(self):
        self.enroll(self.team, self.intake)
        self.continue_team()
        StudentAcademicRecord.objects.filter(semester=self.normal).delete()
        before = list(TeamTermParticipation.objects.values())
        response = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone'})
        self.assertEqual(response.status_code, 200, response.data)
        records = response.data['teams']
        self.assertEqual([r['phase'] for r in records], ['capstone_1', 'capstone_2'])
        self.assertTrue(records[0]['members'][0]['is_enrolled'])
        self.assertFalse(records[1]['members'][0]['is_enrolled'])
        self.assertEqual(records[1]['defense_context']['stage_status'], 'awaiting_stage_setup')
        self.assertTrue(records[1]['phase_is_open'])
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(len({r['record_key'] for r in records}), 2)
        self.assertEqual(list(TeamTermParticipation.objects.values()), before)

    def test_history_stage_filter_preserves_actual_term(self):
        self.continue_team()
        response = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone',
            'intake_id': self.intake.pk, 'stage_key': f'{self.intake.pk}:{self.first.pk}'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data['teams']), 1)
        record = response.data['teams'][0]
        self.assertEqual(record['semester_id'], self.intake.pk)
        self.assertEqual(record['defense_context']['current_stage'], self.first.label)
        self.assertEqual(record['defense_context']['stage_status'], 'passed')
        self.assertEqual([a['defense_stage_id'] for a in record['assessments']], [self.first.pk])

    def test_intakes_are_separate_and_history_options_authorized(self):
        self.continue_team()
        other = self.make_team('Next intake', self.extension)
        response = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone',
            'intake_id': self.intake.pk})
        self.assertNotIn(other.pk, [t['id'] for t in response.data['teams']])
        outsider = get_user_model().objects.create_user(username='outsider', role='student')
        self.client.force_authenticate(outsider)
        response = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone',
            'intake_id': self.intake.pk})
        self.assertEqual(response.data['teams'], [])
        self.assertEqual(response.data['capstone_history']['intakes'], [])

    def test_old_completion_protects_structure_but_not_new_term_grading(self):
        StageGradingConfig.objects.create(defense_stage=self.first, semester=self.intake,
            is_officially_complete=True)
        self.assertTrue(grade_configuration_lock(self.first)[0])
        self.assertFalse(grade_configuration_lock(self.first, self.normal)[0])
        self.assertTrue(grade_configuration_lock(self.first, self.intake)[0])

    def test_setup_history_has_connected_phase_groups_and_read_only_configuration(self):
        self.continue_team()
        before = StageGradingConfig.objects.count()
        response = self.client.get('/api/defense/stages/', {'scope': 'history', 'intake_id': self.intake.pk})
        self.assertEqual(response.status_code, 200, response.data)
        groups = response.data['phase_groups']
        self.assertEqual([g['phase'] for g in groups], ['capstone_1', 'capstone_2'])
        self.assertEqual(groups[1]['stages'], [])
        self.assertTrue(all(g['read_only'] for g in groups))
        self.client.get(f'/api/defense/stages/{self.first.pk}/', {'semester_id': self.normal.pk})
        self.assertEqual(StageGradingConfig.objects.count(), before)

    def test_history_and_dashboard_do_not_restart_a_continued_phase(self):
        self.continue_team()
        from repository.deliverables.services import current_stage_for_team, team_payload
        self.assertIsNone(current_stage_for_team(self.team))
        data = team_payload(self.team, evaluator=self.admin)
        self.assertEqual(data['stages'], [])
        self.assertIsNone(data['current_stage'])

    def test_stage_events_are_captured_once_and_audit_failure_rolls_back(self):
        from authentication_access_control.models import SystemAuditLog
        self.continue_team()
        self.assertEqual(SystemAuditLog.objects.filter(action='capstone.continued').count(), 1)
        history = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone'})
        self.assertTrue(all(any(e['action'] == 'capstone.continued' for e in r['timeline'])
            for r in history.data['teams']))
        progress_before = TeamStageProgress.all_objects.count()
        grade = self.assess(self.team, self.second, term=self.normal)
        from student_teams.services import mark_stage_result
        with patch('student_teams.history_events.record_team_event', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(RuntimeError):
                mark_stage_result(grade, user=self.admin)
        self.assertEqual(TeamStageProgress.all_objects.count(), progress_before)

    def test_pit_grade_totals_and_event_lists_follow_the_same_semester(self):
        from defense.scheduler.models import PitEventGradingConfig
        from grading.grades.models import TeamGrade
        from student_teams.models import StudentTeam
        event = PitEventGradingConfig.objects.create(semester=self.intake,
            year_level='1st Year', event_name='Source expo')
        pit = self.make_team('PIT source')
        pit.level, pit.year_level = StudentTeam.LEVEL_1_PIT, '1st Year'
        pit.save()
        grade = TeamGrade(team=pit, semester=self.intake, scope='pit',
            stage_label=event.event_name, pit_event_config=event, status='published',
            panel_score=85, peer_score=85)
        grade.save(clean=False)
        self.intake.is_active = False
        self.intake.save(update_fields=['is_active'])
        self.normal.is_active = True
        self.normal.save(update_fields=['is_active'])
        current = self.client.get('/api/grading/grades/', {'scope': 'pit'})
        self.assertEqual(current.status_code, 200, current.data)
        self.assertEqual(current.data['counts']['pit'], 0)
        self.assertEqual(current.data['pit_events'], [])
        previous = self.client.get('/api/grading/grades/', {'scope': 'pit', 'semester_id': self.intake.pk})
        self.assertEqual(previous.data['counts']['pit'], 1)
        self.assertEqual([e['id'] for e in previous.data['pit_events']], [event.pk])

    def test_roster_export_keeps_the_same_intake_and_stage_scope(self):
        self.continue_team()
        response = self.client.get('/api/reports/team-roster/', {
            'export_format': 'json',
            'term_context': 'history', 'intake_id': self.intake.pk,
            'stage_key': f'{self.intake.pk}:{self.first.pk}'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data['rows']), 1)
        self.assertEqual(response.data['rows'][0]['period'], self.intake.display_name)

    def test_recorded_adviser_retains_only_the_original_term_after_reassignment(self):
        adviser = get_user_model().objects.create_user(username='source-adviser', role='faculty', is_adviser=True)
        self.team.adviser = adviser
        self.team.save()
        self.continue_team()
        self.team.adviser = None
        self.team.save()
        self.client.force_authenticate(adviser)
        response = self.client.get('/api/teams/', {'scope': 'history', 'level': 'Capstone',
            'workspace': 'adviser', 'intake_id': self.intake.pk})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([r['semester_id'] for r in response.data['teams']], [self.intake.pk])
        self.assertEqual(len(response.data['teams'][0]['assessments']), 2)

    def test_historical_shared_clearance_uses_captured_participants_after_migration(self):
        from student_teams.models import SectionAssignment
        from repository.section_concepts.models import SharedDeliverableSet
        from repository.section_concepts.shared_deliverables import resolve, required_complete
        from student_teams.capstone_lifecycle import recorded_team
        self.team.section = 'BSIT-3A'
        self.team.save()
        section = SectionAssignment.objects.create(semester=self.intake, year_level='3rd Year',
            section='BSIT-3A', project_manager=self.team.leader)
        captured = SharedDeliverableSet.objects.create(section=section, defense_stage=self.first,
            identity='source-proof', project_manager=self.team.leader,
            team_snapshot=[{'id': self.team.pk, 'version': self.team.project_version}],
            requirements=[{'deliverable_id': 'SHARED', 'label': 'Shared clearance',
                'required': True, 'deliverable_type': 'post', 'file_policy': {}}])
        self.continue_team()
        profile = resolve(recorded_team(self.team, self.intake), self.first)
        self.assertIsNotNone(profile)
        self.assertEqual(profile['captured'].pk, captured.pk)
        self.assertFalse(required_complete(profile, 'post'))
