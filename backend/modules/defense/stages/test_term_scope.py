"""Semester setup must not relabel historical stages as a fresh intake."""
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management import tests_capstone_transition as fixtures
from academic_period_management.models import Semester
from defense.stages.models import DefenseStage, StageGradingConfig
from student_teams.models import TeamTermParticipation


class StageSetupTermScopeTests(APITestCase):
    make_team = fixtures.CapstoneTransitionTests.make_team
    enroll = fixtures.CapstoneTransitionTests.enroll
    assess = fixtures.CapstoneTransitionTests.assess
    preview = fixtures.CapstoneTransitionTests.preview
    activate = fixtures.CapstoneTransitionTests.activate

    def setUp(self):
        fixtures.CapstoneTransitionTests.setUp(self)
        DefenseStage.objects.exclude(pk__in=[self.first.pk, self.second.pk]).delete()

    def continue_team(self):
        self.assess(self.team, self.first)
        self.assess(self.team, self.second)
        self.assertEqual(self.activate(self.normal).status_code, 200)
        self.team.refresh_from_db()

    def start_new_intake(self):
        self.continue_team()
        row = self.team.term_participations.get(semester=self.normal)
        row.closed_at = timezone.now()
        row.outcome = 'completed'
        row.save(update_fields=['closed_at', 'outcome'])
        Semester.objects.filter(is_active=True).update(is_active=False)
        self.extension.is_active = True
        self.extension.save(update_fields=['is_active'])
        return self.make_team('Fresh intake', self.extension)

    def test_current_term_excludes_source_phase_and_ignores_history_filters(self):
        self.continue_team()
        before = list(TeamTermParticipation.objects.values())
        response = self.client.get('/api/defense/stages/', {
            'scope': 'active', 'intake_id': self.intake.pk, 'phase': 'capstone_1'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stages'], [])
        self.assertEqual(response.data['active_stages'], [])
        self.assertEqual(response.data['counts']['total'], 0)
        group, = response.data['phase_groups']
        self.assertEqual(group['phase'], 'capstone_2')
        self.assertEqual(group['display_semester'], self.normal.display_name)
        self.assertEqual(group['stages'], [])
        self.assertFalse(group['read_only'])
        self.assertEqual(list(TeamTermParticipation.objects.values()), before)

    def test_fresh_intake_does_not_claim_old_published_stages_or_their_year(self):
        self.start_new_intake()
        # Rollover/lookups can leave an empty new-term grading placeholder.
        StageGradingConfig.objects.create(defense_stage=self.first, semester=self.extension)
        before = list(StageGradingConfig.objects.values())
        response = self.client.get('/api/defense/stages/', {'scope': 'active'})
        self.assertEqual(response.data['stages'], [])
        self.assertEqual(response.data['counts'], {'total': 0, 'active': 0, 'inactive': 0})
        group, = response.data['phase_groups']
        self.assertEqual(group['semester_id'], self.extension.pk)
        self.assertEqual(group['display_semester'], self.extension.display_name)
        self.assertEqual(group['phase'], 'capstone_1')
        self.assertEqual(group['stages'], [])
        self.assertEqual(list(StageGradingConfig.objects.values()), before)

    def test_history_defaults_to_recorded_intake_and_preserves_each_actual_year(self):
        self.start_new_intake()
        response = self.client.get('/api/defense/stages/', {'scope': 'history'})
        self.assertEqual(response.data['capstone_history']['selected_intake_id'], self.intake.pk)
        groups = response.data['phase_groups']
        self.assertEqual([g['display_semester'] for g in groups],
            [self.intake.display_name, self.normal.display_name])
        self.assertEqual([g['phase'] for g in groups], ['capstone_1', 'capstone_2'])
        self.assertTrue(all(g['read_only'] for g in groups))
        self.assertEqual({s['semester_id'] for s in response.data['stages']}, {self.intake.pk})
        self.assertTrue(all(s['history_read_only'] for s in response.data['stages']))
        self.assertEqual(response.data['counts']['total'], 2)
        selected = self.client.get('/api/defense/stages/', {'scope': 'history',
            'intake_id': self.intake.pk, 'stage_key': f'{self.intake.pk}:{self.first.pk}'})
        self.assertEqual([s['id'] for s in selected.data['stages']], [self.first.pk])
        self.assertEqual(selected.data['counts']['total'], 1)

    def test_no_current_roster_does_not_restore_global_historical_stages(self):
        self.continue_team()
        Semester.objects.filter(is_active=True).update(is_active=False)
        self.extension.is_active = True
        self.extension.save(update_fields=['is_active'])
        response = self.client.get('/api/defense/stages/')
        self.assertEqual(response.data['stages'], [])
        self.assertEqual(response.data['phase_groups'], [])
        self.assertEqual(response.data['counts']['total'], 0)

    def test_new_draft_and_mutation_response_use_its_own_sequence(self):
        self.start_new_intake()
        response = self.client.post('/api/defense/stages/', {
            'label': 'New intake workshop', 'display_order': 3, 'is_active': False}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        stage_id = response.data['stage']['id']
        self.assertEqual([s['id'] for s in response.data['stages']], [stage_id])
        self.assertEqual([s['id'] for s in response.data['sequence_stages']],
            [stage_id])
        self.assertEqual(response.data['stage']['display_order'], 1)
        self.assertEqual(response.data['phase_groups'][0]['stages'][0]['semester_id'], self.extension.pk)
        refreshed = self.client.get('/api/defense/stages/')
        self.assertEqual(refreshed.data['stages'], response.data['stages'])
        updated = self.client.patch(f'/api/defense/stages/{stage_id}/',
            {'description': 'Current setup'}, format='json')
        self.assertEqual([s['id'] for s in updated.data['stages']], [stage_id])
        self.assertEqual(updated.data['phase_groups'][0]['display_semester'], self.extension.display_name)

    def test_explicit_new_term_configuration_can_reuse_a_definition(self):
        self.start_new_intake()
        # Actual setup, rather than the publication flag or an empty lookup row.
        response = self.client.patch(
            f'/api/defense/stages/{self.first.pk}/grading-config/?semester_id={self.extension.pk}',
            {'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.get('/api/defense/stages/')
        self.assertEqual([s['id'] for s in response.data['stages']], [self.first.pk])
        self.assertEqual(response.data['stages'][0]['semester_id'], self.extension.pk)

    def test_fresh_batch_can_create_the_same_stage_name_at_position_one(self):
        from defense.configuration_locks import context_submissions
        from repository.deliverables.services import get_deliverable_definitions_for_scope
        from student_teams.capstone_context import phase_requirements
        from grading.grades.models import TeamGrade
        fresh = self.start_new_intake()
        old_ids = [self.first.pk, self.second.pk]
        before = list(DefenseStage.objects.filter(pk__in=old_ids).order_by('pk').values())
        files = list(self.team.deliverable_submissions.values())
        grades = list(TeamGrade.all_objects.filter(team=self.team).values())
        configs = list(StageGradingConfig.objects.filter(defense_stage_id__in=old_ids).values())
        response = self.client.post('/api/defense/stages/', {
            'label': self.first.label, 'code': self.first.code,
            'display_order': 1, 'semester_id': self.extension.pk, 'is_active': True,
            'deliverables': [{'deliverable_id': 'PRE', 'label': 'New batch paper',
                'deliverable_type': 'pre', 'required': True}],
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        stage = DefenseStage.objects.get(pk=response.data['stage']['id'])
        self.assertNotEqual(stage.pk, self.first.pk)
        self.assertEqual(stage.setup_semester, self.extension)
        self.assertEqual(stage.display_order, 1)
        self.assertFalse(response.data['stage']['structure_locked'])
        self.assertFalse(context_submissions(stage).exists())
        self.assertIsNone(response.data['stage']['previous_stage_id'])
        self.assertEqual([r['id'] for r in phase_requirements(fresh)], [stage.pk])
        self.assertEqual(get_deliverable_definitions_for_scope('capstone', self.extension.pk,
            self.first.label)[0]['label'], 'New batch paper')
        self.assertEqual(get_deliverable_definitions_for_scope('capstone', self.intake.pk,
            self.first.label)[0]['label'], 'Stage paper')
        duplicate = self.client.post('/api/defense/stages/', {'label': self.first.label}, format='json')
        self.assertEqual(duplicate.status_code, 400)
        updated = self.client.patch(f'/api/defense/stages/{stage.pk}/',
            {'description': 'Fresh batch only'}, format='json')
        self.assertEqual(updated.status_code, 200, updated.data)
        self.assertEqual(before, list(DefenseStage.objects.filter(pk__in=old_ids).order_by('pk').values()))
        self.assertEqual(files, list(self.team.deliverable_submissions.values()))
        self.assertEqual(grades, list(TeamGrade.all_objects.filter(team=self.team).values()))
        self.assertEqual(configs, list(StageGradingConfig.objects.filter(defense_stage_id__in=old_ids).values()))

    def test_stale_draft_position_cannot_reorder_the_previous_batch(self):
        self.start_new_intake()
        before = list(DefenseStage.objects.order_by('pk').values())
        response = self.client.post('/api/defense/stages/', {
            'label': self.first.label, 'display_order': 4, 'is_active': False}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['stage']['display_order'], 1)
        self.assertEqual(before, list(DefenseStage.objects.filter(
            pk__in=[r['id'] for r in before]).order_by('pk').values()))

    def test_reorder_and_delete_are_confined_to_the_new_batch(self):
        self.start_new_intake()
        old = list(DefenseStage.objects.order_by('pk').values())
        created = [self.client.post('/api/defense/stages/', {'label': label}, format='json')
            for label in (self.first.label, self.second.label)]
        self.assertTrue(all(r.status_code == 201 for r in created), [r.data for r in created])
        ids = [r.data['stage']['id'] for r in created]
        reordered = self.client.post('/api/defense/stages/reorder/', {'stage_ids': ids[::-1]}, format='json')
        self.assertEqual(reordered.status_code, 200, reordered.data)
        self.assertEqual([r['id'] for r in reordered.data['stages']], ids[::-1])
        invalid = self.client.post('/api/defense/stages/reorder/',
            {'stage_ids': [self.first.pk, *ids]}, format='json')
        self.assertEqual(invalid.status_code, 400)
        deleted = self.client.delete(f'/api/defense/stages/{ids[0]}/')
        self.assertEqual(deleted.status_code, 200, deleted.data)
        self.assertEqual(old, list(DefenseStage.objects.filter(
            pk__in=[r['id'] for r in old]).order_by('pk').values()))

    def test_old_semester_creation_request_is_rejected_without_writing(self):
        self.start_new_intake()
        before = DefenseStage.objects.count()
        response = self.client.post('/api/defense/stages/', {
            'label': 'Stale term draft', 'semester_id': self.intake.pk}, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(DefenseStage.objects.count(), before)

    def test_owned_stage_can_continue_with_the_same_intake_but_not_a_fresh_batch(self):
        DefenseStage.objects.all().delete()
        stages = []
        for label in ('Intake discovery', 'Intake review'):
            response = self.client.post('/api/defense/stages/', {'label': label,
                'deliverables': [{'deliverable_id': 'PRE', 'label': 'Stage paper',
                    'deliverable_type': 'pre', 'required': True}]}, format='json')
            self.assertEqual(response.status_code, 201, response.data)
            stages.append(DefenseStage.objects.get(pk=response.data['stage']['id']))
        first, pending = stages
        self.assess(self.team, first)
        response = self.activate(self.normal)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        response = self.client.patch(
            f'/api/defense/stages/{pending.pk}/grading-config/?semester_id={self.normal.pk}',
            {'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        # An independent new intake cannot claim that same scoped definition.
        Semester.objects.filter(is_active=True).update(is_active=False)
        self.extension.is_active = True
        self.extension.save(update_fields=['is_active'])
        self.make_team('Separate batch', self.extension)
        response = self.client.patch(
            f'/api/defense/stages/{pending.pk}/grading-config/?semester_id={self.extension.pk}',
            {'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0}, format='json')
        self.assertEqual(response.status_code, 409, response.data)
        self.assertFalse(StageGradingConfig.objects.filter(
            defense_stage=pending, semester=self.extension).exists())
