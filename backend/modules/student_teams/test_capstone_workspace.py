"""Cross-workspace continuity, historic authority, and phase isolation."""
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management import tests_capstone_transition as fixtures
from academic_period_management.models import Semester
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from .models import TeamTermParticipation
from .capstone_lifecycle import capture_participation


class CapstoneWorkspaceTests(APITestCase):
    make_team = fixtures.CapstoneTransitionTests.make_team
    enroll = fixtures.CapstoneTransitionTests.enroll
    assess = fixtures.CapstoneTransitionTests.assess
    preview = fixtures.CapstoneTransitionTests.preview
    activate = fixtures.CapstoneTransitionTests.activate

    def setUp(self):
        fixtures.CapstoneTransitionTests.setUp(self)
        self.adviser = get_user_model().objects.create_user(username='phase-adviser', role='faculty', is_adviser=True)
        self.team.adviser = self.adviser
        self.team.save(update_fields=['adviser'])
        self.assess(self.team, self.first)
        self.assess(self.team, self.second)
        self.assertEqual(self.activate(self.normal).status_code, 200)
        self.team.refresh_from_db()

    def files(self, **params):
        self.client.force_authenticate(self.adviser)
        return self.client.get('/api/repository/deliverables/', {
            'workspace': 'adviser', 'scope': 'capstone', 'capstone_view': 'ongoing', **params})

    def grades(self, **params):
        self.client.force_authenticate(self.admin)
        return self.client.get('/api/grading/grades/', {
            'workspace': 'operations', 'scope': 'capstone', 'capstone_view': 'ongoing', **params})

    def evidence(self):
        return [list(model.all_objects.values()) if hasattr(model, 'all_objects') else list(model.objects.values())
            for model in (TeamGrade, DeliverableSubmission, TeamTermParticipation, StageGradingConfig)]

    def test_adviser_stage_sequence_keeps_completed_stages_when_current_phase_is_empty(self):
        before = self.evidence()
        response = self.files(stage_sequence='all')
        self.assertEqual(response.status_code, 200, response.data)
        workspace = response.data['capstone_workspace']
        self.assertEqual(workspace['current_phase']['semester_id'], self.normal.pk)
        self.assertEqual(workspace['current_phase']['stage_count'], 0)
        self.assertEqual([o['stage_id'] for o in workspace['stage_options']], [self.first.pk, self.second.pk])
        self.assertEqual(workspace['selected_stage_key'], f'{self.intake.pk}:{self.second.pk}')
        self.assertEqual(response.data['selected_stage'], self.second.label)
        self.assertTrue(response.data['teams'][0]['selected_stage']['read_only'])
        linked = self.files(stage_sequence='all', stage_label=self.first.label)
        self.assertEqual(linked.data['capstone_workspace']['selected_stage_key'], f'{self.intake.pk}:{self.first.pk}')
        self.assertEqual(self.evidence(), before)

    def test_stage_sequence_uses_term_and_stage_id_for_repeated_labels(self):
        current = DefenseStage.objects.create(label=self.first.label, setup_semester=self.normal, display_order=1)
        current.deliverables.create(deliverable_id='NEW', label='New phase paper', deliverable_type='pre', required=True)
        response = self.files(stage_sequence='all')
        workspace = response.data['capstone_workspace']
        self.assertEqual(workspace['selected_stage_key'], f'{self.normal.pk}:{current.pk}')
        self.assertEqual(len(workspace['stage_options']), 3)
        self.assertFalse(response.data['teams'][0]['selected_stage']['read_only'])
        source = self.files(stage_sequence='all', stage_key=f'{self.intake.pk}:{self.first.pk}')
        self.assertEqual(source.data['active_semester']['id'], self.intake.pk)
        self.assertTrue(source.data['teams'][0]['selected_stage']['read_only'])
        self.assertEqual(source.data['teams'][0]['selected_stage']['grade']['status'], 'published')
        self.assertEqual(self.files(stage_sequence='all', stage_key='unrelated').status_code, 400)
        self.assertEqual(self.files(stage_sequence='all', stage_key=f'{self.intake.pk}:{self.first.pk}',
            phase_semester_id=self.normal.pk).status_code, 400)

    def test_grade_sequence_has_both_phases_with_current_phase_statistics(self):
        before = self.evidence()
        response = self.grades(include_phases='1')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['active_semester']['id'], self.normal.pk)
        self.assertEqual(response.data['counts']['filtered'], 0)
        self.assertEqual(response.data['phase_statistics']['total_teams'], 1)
        self.assertEqual(response.data['phase_statistics']['fully_graded_teams'], 0)
        phases = response.data['capstone_phases']
        self.assertEqual([p['phase'] for p in phases], ['capstone_1', 'capstone_2'])
        self.assertEqual([p['read_only'] for p in phases], [True, False])
        self.assertEqual(len(phases[0]['payload']['grades']), 2)
        self.assertEqual(phases[0]['payload']['phase_statistics']['fully_graded_teams'], 1)
        self.assertEqual(phases[1]['payload']['grades'], [])
        self.assertEqual(phases[1]['payload']['capstone_stages'], [])
        self.assertNotIn('capstone_phases', phases[0]['payload'])
        self.assertEqual(self.evidence(), before)

    def test_continuation_has_two_phases_even_without_destination_setup(self):
        before = self.evidence()
        response = self.files()
        self.assertEqual(response.status_code, 200, response.data)
        data = response.data['capstone_workspace']
        self.assertEqual(data['batch_id'], str(self.intake.pk))
        self.assertEqual(data['phase_semester_id'], self.normal.pk)
        self.assertEqual([g['phase'] for g in data['phase_groups']], ['capstone_1', 'capstone_2'])
        self.assertEqual([g['read_only'] for g in data['phase_groups']], [True, False])
        self.assertEqual(data['phase_groups'][1]['stage_count'], 0)
        self.assertEqual(response.data['stage_options'], [])
        self.assertEqual([t['id'] for t in response.data['teams']], [self.team.pk])
        self.assertEqual(self.files(capstone_view='history').data['teams'], [])
        self.assertEqual(self.evidence(), before)

    def test_adviser_reads_original_files_and_grades_in_completed_phase(self):
        before = self.evidence()
        response = self.files(phase_semester_id=self.intake.pk, stage_label=self.first.label)
        self.assertEqual(response.status_code, 200, response.data)
        team = response.data['teams'][0]
        self.assertEqual(team['semester_id'], self.intake.pk)
        stage = team['selected_stage']
        self.assertTrue(stage['read_only'])
        self.assertEqual(stage['grade']['status'], 'published')
        self.assertEqual(stage['semester_id'], self.intake.pk)
        self.assertTrue(stage['pre'][0]['uploaded'])
        self.assertFalse(stage['pre'][0]['can_upload'])
        self.assertFalse(stage['pre'][0]['can_faculty_review'])
        self.assertFalse(stage['can_cancel_endorsement'])
        self.assertEqual(self.evidence(), before)

    def test_grade_summary_and_stage_groups_follow_selected_phase(self):
        before = self.evidence()
        current = self.grades()
        self.assertEqual(current.status_code, 200, current.data)
        self.assertEqual(current.data['grades'], [])
        self.assertEqual(current.data['capstone_stages'], [])
        source = self.grades(phase_semester_id=self.intake.pk)
        self.assertEqual(source.status_code, 200, source.data)
        self.assertEqual(source.data['active_semester']['id'], self.intake.pk)
        self.assertEqual(len(source.data['grades']), 2)
        self.assertEqual({g['semester_id'] for g in source.data['grades']}, {self.intake.pk})
        self.assertEqual({s['id'] for s in source.data['capstone_stages']}, {self.first.pk, self.second.pk})
        self.assertEqual(self.evidence(), before)

    def test_ended_batch_moves_to_history_beside_new_intake(self):
        row = capture_participation(self.team)
        row.closed_at, row.outcome = timezone.now(), 'completed'
        row.save()
        Semester.objects.filter(is_active=True).update(is_active=False)
        self.extension.is_active = True
        self.extension.save(update_fields=['is_active'])
        fresh = self.make_team('Fresh', self.extension)
        fresh.adviser, fresh.intake_semester = self.adviser, self.extension
        fresh.save(update_fields=['adviser', 'intake_semester'])
        capture_participation(fresh)
        current = self.files()
        self.assertEqual([t['id'] for t in current.data['teams']], [fresh.pk])
        self.assertEqual(current.data['capstone_workspace']['batch_id'], str(self.extension.pk))
        old = self.files(capstone_view='history')
        self.assertEqual([t['id'] for t in old.data['teams']], [self.team.pk])
        self.assertEqual([g['phase'] for g in old.data['capstone_workspace']['phase_groups']], ['capstone_1', 'capstone_2'])
        self.assertTrue(all(g['read_only'] for g in old.data['capstone_workspace']['phase_groups']))
        self.assertTrue(self.grades(capstone_view='history').data['capstone_workspace']['read_only'])

    def test_recorded_adviser_sees_only_previously_assigned_phase_after_reassignment(self):
        from defensys_backend.media_access import _can_read_submission
        source_file = DeliverableSubmission.objects.get(team=self.team, stage_label=self.first.label)
        replacement = get_user_model().objects.create_user(username='replacement', role='faculty', is_adviser=True)
        self.team.adviser = replacement
        self.team.save(update_fields=['adviser'])
        response = self.files()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([g['semester_id'] for g in response.data['capstone_workspace']['phase_groups']], [self.intake.pk])
        self.assertTrue(response.data['teams'][0]['selected_stage']['read_only'])
        self.assertEqual(self.files(phase_semester_id=self.normal.pk).data['teams'], [])
        self.assertTrue(_can_read_submission(self.adviser, source_file))
        stranger = get_user_model().objects.create_user(username='file-stranger', role='faculty', is_adviser=True)
        source_file.status = 'pending'
        source_file.save()
        self.assertFalse(_can_read_submission(stranger, source_file))

    def test_historical_names_and_roster_use_source_snapshot(self):
        from .models import TeamMembership
        old_leader = self.team.leader_id
        replacement = get_user_model().objects.create_user(username='new-leader', first_name='New', role='student')
        self.team.name, self.team.project_title, self.team.leader = 'Renamed current team', 'New title', replacement
        self.team.save(update_fields=['name', 'project_title', 'leader'])
        TeamMembership.objects.filter(team=self.team).delete()
        TeamMembership.objects.create(team=self.team, student=replacement, is_leader=True)
        source = self.files(phase_semester_id=self.intake.pk).data['teams'][0]
        self.assertEqual(source['name'], 'Cedar')
        self.assertEqual([m['id'] for m in source['members']], [old_leader])
        self.assertEqual(len(self.files(phase_semester_id=self.intake.pk, search='Cedar').data['teams']), 1)
        self.assertEqual(self.files(phase_semester_id=self.intake.pk, search='Renamed current team').data['teams'], [])
        grades = self.grades(phase_semester_id=self.intake.pk).data['grades']
        self.assertTrue(all(g['team_name'] == 'Cedar' and g['read_only'] for g in grades))
        self.assertTrue(all([m['id'] for m in g['members']] == [old_leader] for g in grades))
        filtered = self.grades(phase_semester_id=self.intake.pk, search='Cedar', year_level='3rd Year')
        self.assertEqual(len(filtered.data['grades']), 2)
        self.assertIn('3rd Year', filtered.data['year_levels'])
        self.assertEqual(self.grades(phase_semester_id=self.intake.pk, search='Renamed current team').data['grades'], [])

    def test_masterlist_preserves_selected_phase_and_excludes_foreign_batches(self):
        self.client.force_authenticate(self.admin)
        params = {'workspace': 'operations', 'scope': 'capstone', 'capstone_view': 'ongoing',
            'batch_id': str(self.intake.pk), 'phase_semester_id': str(self.intake.pk),
            'semester_id': str(self.intake.pk), 'defense_stage_id': str(self.first.pk),
            'entity': 'teams', 'coverage': 'semester'}
        response = self.client.get('/api/grading/grades/masterlist/', params)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row['id'] for row in response.data['rows']], [self.team.pk])
        self.assertEqual(response.data['context']['semester_id'], self.intake.pk)
        other = self.client.get('/api/grading/grades/masterlist/', {**params, 'batch_id': str(self.extension.pk)})
        self.assertEqual(other.data['rows'], [])

    def test_foreign_batch_term_and_invalid_filters_cannot_expand_scope(self):
        stranger = get_user_model().objects.create_user(username='stranger', role='faculty', is_adviser=True)
        self.adviser = stranger
        self.assertEqual(self.files(batch_id=self.intake.pk, phase_semester_id=self.intake.pk).data['teams'], [])
        for params in ({'capstone_view': 'all'}, {'batch_id': 'bad'}, {'phase_semester_id': 'bad'}):
            self.assertEqual(self.files(**params).status_code, 400)

    def test_old_phase_group_write_cannot_target_same_named_current_stage(self):
        stage = DefenseStage.objects.create(label=self.first.label, setup_semester=self.normal, display_order=1)
        config = StageGradingConfig.objects.create(defense_stage=stage, semester=self.normal)
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/grading/grades/group-settings/?workspace=operations&semester_id={self.intake.pk}',
            {'scope': 'capstone', 'stage_label': self.first.label, 'peer_grading_enabled': True}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        config.refresh_from_db()
        self.assertFalse(config.peer_grading_enabled)
        source = self.grades(phase_semester_id=self.intake.pk)
        current = self.grades(phase_semester_id=self.normal.pk)
        self.assertNotIn(stage.pk, {s['id'] for s in source.data['capstone_stages']})
        self.assertEqual([s['id'] for s in current.data['capstone_stages']], [stage.pk])

    def test_past_phase_review_cannot_target_same_named_current_stage(self):
        stage = DefenseStage.objects.create(label=self.first.label, setup_semester=self.normal, display_order=1)
        stage.deliverables.create(deliverable_id='NEW', label='New paper', deliverable_type='pre', required=True)
        submission = DeliverableSubmission.objects.create(team=self.team, stage_label=stage.label,
            deliverable_id='NEW', deliverable_type='pre', label='New paper', file_name='new.pdf', status='pending')
        self.client.force_authenticate(self.adviser)
        response = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.pk, 'stage_label': stage.label, 'deliverable_id': 'NEW', 'status': 'accepted'},
            QUERY_STRING=f'workspace=adviser&scope=capstone&capstone_view=ongoing&phase_semester_id={self.intake.pk}', format='json')
        self.assertEqual(response.status_code, 403, response.data)
        submission.refresh_from_db()
        self.assertEqual(submission.status, 'pending')
