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