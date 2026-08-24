from datetime import date, time

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.grading_config import get_or_create_stage_grading_config
from grading.grades.services import weights_for_schedule
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam
from .models import DefenseStage, StageGradingConfig


User = get_user_model()


class DefenseStageApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.client.force_authenticate(user=self.admin)

    def test_default_stages_are_seeded_by_migration(self):
        response = self.client.get('/api/defense/stages/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['total'], 3)
        self.assertEqual(
            [stage['label'] for stage in response.data['stages']],
            ['Concept Proposal', 'Project Proposal', 'Final Defense'],
        )
        self.assertEqual(response.data['stages'][0]['code'], 'concept-proposal')
        self.assertIsNone(response.data['stages'][0]['previous_stage_label'])
        self.assertEqual(response.data['stages'][1]['previous_stage_label'], 'Concept Proposal')

    def test_admin_can_create_stage_with_generated_code(self):
        response = self.client.post(
            '/api/defense/stages/',
            {
                'label': 'Prototype Demo',
                'description': 'A custom checkpoint stage.',
                'display_order': 4,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['stage']['code'], 'prototype-demo')
        self.assertEqual(response.data['counts']['total'], 4)
        self.assertTrue(DefenseStage.objects.filter(label='Prototype Demo').exists())

    def test_admin_can_create_stage_with_custom_code(self):
        response = self.client.post(
            '/api/defense/stages/',
            {
                'label': 'Design Assessment',
                'code': 'custom-design-stage',
                'display_order': 5,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['stage']['code'], 'custom-design-stage')
        stage = DefenseStage.objects.get(label='Design Assessment')
        self.assertEqual(stage.code, 'custom-design-stage')

    def test_admin_can_update_stage_code(self):
        stage = DefenseStage.objects.get(label='Final Defense')
        response = self.client.patch(
            f'/api/defense/stages/{stage.id}/',
            {
                'code': 'custom-final-code',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        stage.refresh_from_db()
        self.assertEqual(stage.code, 'custom-final-code')

    def test_create_stage_with_blank_deliverable_label_is_rejected(self):
        response = self.client.post(
            '/api/defense/stages/',
            {
                'label': 'Test Stage with Blank Deliverable',
                'deliverables': [
                    {
                        'deliverable_id': 'D1',
                        'label': '  ',
                        'deliverable_type': 'pre',
                        'required': True,
                    }
                ]
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('deliverables', response.data)

    def test_duplicate_label_is_rejected_case_insensitive(self):
        response = self.client.post(
            '/api/defense/stages/',
            {'label': 'concept proposal'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_update_stage_label_order_and_active_status(self):
        stage = DefenseStage.objects.get(label='Final Defense')

        response = self.client.patch(
            f'/api/defense/stages/{stage.id}/',
            {
                'label': 'Final Oral Defense',
                'display_order': 5,
                'is_active': False,
            },
            format='json',
        )

        stage.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(stage.label, 'Final Oral Defense')
        self.assertEqual(stage.code, 'final-oral-defense')
        self.assertFalse(stage.is_active)
        self.assertEqual(response.data['counts']['active'], 2)

    def test_non_admin_can_read_but_cannot_create(self):
        student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)

        read_response = self.client.get('/api/defense/stages/')
        create_response = self.client.post(
            '/api/defense/stages/',
            {'label': 'Blocked Stage'},
            format='json',
        )

        self.assertEqual(read_response.status_code, 200)
        self.assertEqual(create_response.status_code, 403)

    def test_admin_can_reorder_stages(self):
        s1 = DefenseStage.objects.get(label='Concept Proposal')
        s2 = DefenseStage.objects.get(label='Project Proposal')
        s3 = DefenseStage.objects.get(label='Final Defense')

        # Reverse the order: Final Defense -> Project Proposal -> Concept Proposal
        response = self.client.post(
            '/api/defense/stages/reorder/',
            {'stage_ids': [s3.id, s2.id, s1.id]},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        s3.refresh_from_db()
        s2.refresh_from_db()
        s1.refresh_from_db()

        self.assertEqual(s3.display_order, 1)
        self.assertEqual(s2.display_order, 2)
        self.assertEqual(s1.display_order, 3)

        # Check prerequisite chaining in response
        stages_data = response.data['stages']
        self.assertEqual(stages_data[0]['label'], 'Final Defense')
        self.assertIsNone(stages_data[0]['previous_stage_label'])
        self.assertEqual(stages_data[1]['label'], 'Project Proposal')
        self.assertEqual(stages_data[1]['previous_stage_label'], 'Final Defense')
        self.assertEqual(stages_data[2]['label'], 'Concept Proposal')
        self.assertEqual(stages_data[2]['previous_stage_label'], 'Project Proposal')

    def test_reorder_rejects_invalid_ids(self):
        response = self.client.post(
            '/api/defense/stages/reorder/',
            {'stage_ids': [99999]},
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    def test_reorder_rejects_empty_ids(self):
        response = self.client.post(
            '/api/defense/stages/reorder/',
            {'stage_ids': []},
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    def test_creating_stage_at_position_shifts_subsequent_stages(self):
        # Insert a stage at display_order=1 (Start of sequence)
        response = self.client.post(
            '/api/defense/stages/',
            {
                'label': 'Title Defense',
                'display_order': 1,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)
        
        stages = list(DefenseStage.objects.all().order_by('display_order'))
        self.assertEqual([s.label for s in stages], ['Title Defense', 'Concept Proposal', 'Project Proposal', 'Final Defense'])
        self.assertEqual([s.display_order for s in stages], [1, 2, 3, 4])

    def test_non_admin_cannot_reorder(self):
        student = User.objects.create_user(
            username='student-reorder',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.post(
            '/api/defense/stages/reorder/',
            {'stage_ids': [1, 2, 3]},
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_dashboard_counts_active_defense_stages(self):
        DefenseStage.objects.filter(label='Final Defense').update(is_active=False)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['active_defense_stages'], 2)
        self.assertEqual(response.data['migration']['phase'], 15)


class StageGradingConfigApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-weights',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.stage = DefenseStage.objects.get(label='Concept Proposal')
        self.client.force_authenticate(user=self.admin)

    def test_grading_config_defaults_to_50_30_20(self):
        response = self.client.get(
            f'/api/defense/stages/{self.stage.id}/grading-config/',
            {'semester_id': self.semester.id},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        config = response.data['grading_config']
        self.assertEqual(config['panel_weight'], 50)
        self.assertEqual(config['adviser_weight'], 30)
        self.assertEqual(config['peer_weight'], 20)
        self.assertTrue(
            StageGradingConfig.objects.filter(
                defense_stage=self.stage,
                semester=self.semester,
            ).exists(),
        )

    def test_grading_config_patch_rejects_invalid_total(self):
        response = self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {
                'panel_weight': 60,
                'adviser_weight': 30,
                'peer_weight': 30,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_grading_config_patch_updates_dynamic_weights(self):
        response = self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {
                'panel_weight': 60,
                'adviser_weight': 25,
                'peer_weight': 15,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['grading_config']['panel_weight'], 60)

        config = StageGradingConfig.objects.get(
            defense_stage=self.stage,
            semester=self.semester,
        )
        self.assertEqual(config.panel_weight, 60)
        self.assertEqual(config.adviser_weight, 25)
        self.assertEqual(config.peer_weight, 15)

    def test_grading_config_weights_patch_preserves_assigned_rubrics(self):
        panel_rubric = Rubric.objects.create(
            name='Stage Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
        )
        config = get_or_create_stage_grading_config(self.stage, self.semester)
        config.panel_rubric = panel_rubric
        config.save(update_fields=['panel_rubric', 'updated_at'])

        response = self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {
                'panel_weight': 55,
                'adviser_weight': 25,
                'peer_weight': 20,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        config.refresh_from_db()
        self.assertEqual(config.panel_rubric_id, panel_rubric.id)
        self.assertEqual(config.panel_weight, 55)

    def test_grading_config_patch_updates_rubrics(self):
        panel_rubric = Rubric.objects.create(
            name='Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
        )
        adviser_rubric = Rubric.objects.create(
            name='Adviser Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_ADVISER,
            status=Rubric.STATUS_PUBLISHED,
        )
        peer_rubric = Rubric.objects.create(
            name='Peer Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
        )

        response = self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {
                'panel_rubric_id': panel_rubric.id,
                'adviser_rubric_id': adviser_rubric.id,
                'peer_rubric_id': peer_rubric.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        config = StageGradingConfig.objects.get(
            defense_stage=self.stage,
            semester=self.semester,
        )
        self.assertEqual(config.panel_rubric_id, panel_rubric.id)
        self.assertEqual(config.adviser_rubric_id, adviser_rubric.id)
        self.assertEqual(config.peer_rubric_id, peer_rubric.id)

    def test_grading_config_patch_reassociates_rubrics(self):
        other_stage = DefenseStage.objects.create(label='Other Stage', display_order=10)
        panel_rubric = Rubric.objects.create(
            name='Other Stage Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=other_stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
        )

        response = self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {
                'panel_rubric_id': panel_rubric.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        config = StageGradingConfig.objects.get(
            defense_stage=self.stage,
            semester=self.semester,
        )
        self.assertEqual(config.panel_rubric_id, panel_rubric.id)
        
        # Verify the rubric's defense stage was updated in the DB
        panel_rubric.refresh_from_db()
        self.assertEqual(panel_rubric.defense_stage_id, self.stage.id)

    def test_stage_detail_includes_grading_config(self):
        get_or_create_stage_grading_config(self.stage, self.semester)

        response = self.client.get(
            f'/api/defense/stages/{self.stage.id}/?semester_id={self.semester.id}',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('grading_config', response.data)
        self.assertEqual(response.data['grading_config']['panel_weight'], 50)

    def test_weights_for_schedule_uses_stage_config(self):
        config = get_or_create_stage_grading_config(self.stage, self.semester)
        config.panel_weight = 55
        config.adviser_weight = 25
        config.peer_weight = 20
        config.save()

        student = User.objects.create_user(
            username='4088',
            password='pass12345',
            role='student',
        )
        team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=student,
        )
        rubric = Rubric.objects.create(
            name='Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )
        schedule = DefenseSchedule.objects.create(
            team=team,
            semester=self.semester,
            defense_stage=self.stage,
            rubric=rubric,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            status=DefenseSchedule.STATUS_SCHEDULED,
            scheduled_date=date(2026, 5, 20),
            start_time=time(9, 0),
            room='Room 101',
        )

        weights = weights_for_schedule(schedule)
        self.assertEqual(weights['panel_weight'], 55)
        self.assertEqual(weights['adviser_weight'], 25)
        self.assertEqual(weights['peer_weight'], 20)

    def test_retroactive_weights_sync(self):
        from grading.grades.models import TeamGrade

        # Create students and teams
        student1 = User.objects.create_user(
            username='student-sync-test-1',
            password='pass12345',
            role='student',
        )
        team_pending = StudentTeam.objects.create(
            name='Sync Team Pending',
            project_title='Sync Project 1',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=student1,
        )

        student2 = User.objects.create_user(
            username='student-sync-test-2',
            password='pass12345',
            role='student',
        )
        team_published = StudentTeam.objects.create(
            name='Sync Team Published',
            project_title='Sync Project 2',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=student2,
        )

        # Create two TeamGrade records
        pending_grade = TeamGrade.objects.create(
            team=team_pending,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            defense_stage=self.stage,
            stage_label=self.stage.label,
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
            status=TeamGrade.STATUS_PENDING,
        )
        published_grade = TeamGrade.objects.create(
            team=team_published,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            defense_stage=self.stage,
            stage_label=self.stage.label,
            panel_score=85,
            adviser_score=85,
            peer_score=85,
            final_grade=85,
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED,
        )

        # Save stage config with different weights
        config = get_or_create_stage_grading_config(self.stage, self.semester)
        config.panel_weight = 60
        config.adviser_weight = 25
        config.peer_weight = 15
        config.save()

        # Check pending grade has updated weights
        pending_grade.refresh_from_db()
        self.assertEqual(pending_grade.panel_weight, 60)
        self.assertEqual(pending_grade.adviser_weight, 25)
        self.assertEqual(pending_grade.peer_weight, 15)

        # Check published grade has NOT updated weights
        published_grade.refresh_from_db()
        self.assertEqual(published_grade.panel_weight, 50)
        self.assertEqual(published_grade.adviser_weight, 30)
        self.assertEqual(published_grade.peer_weight, 20)

    def test_stage_with_schedule_is_locked_and_cannot_be_updated_or_deleted(self):
        stage = DefenseStage.objects.get(label='Concept Proposal')

        student = User.objects.create_user(username='sched-team-lead', password='pass12345', role='student')
        team = StudentTeam.objects.create(
            name='Sched Team',
            project_title='Sched Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=student,
        )
        DefenseSchedule.objects.create(
            team=team,
            defense_stage=stage,
            semester=self.semester,
            scheduled_date=date(2026, 9, 1),
            start_time=time(9, 0),
            slot_duration=60,
            room='Room 101',
        )

        res_get = self.client.get('/api/defense/stages/')
        stage_data = next(s for s in res_get.data['stages'] if s['id'] == stage.id)
        self.assertTrue(stage_data['is_locked'])

        res_patch = self.client.patch(
            f'/api/defense/stages/{stage.id}/',
            {'label': 'Renamed Concept Proposal'},
            format='json',
        )
        self.assertEqual(res_patch.status_code, 400)

        res_del = self.client.delete(f'/api/defense/stages/{stage.id}/')
        self.assertEqual(res_del.status_code, 409)

    def test_officially_completed_stage_is_locked(self):
        stage = DefenseStage.objects.get(label='Concept Proposal')
        config = get_or_create_stage_grading_config(stage, self.semester)
        config.is_officially_complete = True
        config.save()

        res_get = self.client.get('/api/defense/stages/')
        stage_data = next(s for s in res_get.data['stages'] if s['id'] == stage.id)
        self.assertTrue(stage_data['is_locked'])

        res_config = self.client.patch(
            f'/api/defense/stages/{stage.id}/grading-config/?semester_id={self.semester.id}',
            {'panel_weight': 60, 'adviser_weight': 20, 'peer_weight': 20},
            format='json',
        )
        self.assertEqual(res_config.status_code, 400)