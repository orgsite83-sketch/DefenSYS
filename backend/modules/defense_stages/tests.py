from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from .models import DefenseStage


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
        response = self.client.get('/api/defense-stages/')

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
            '/api/defense-stages/',
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
            '/api/defense-stages/',
            {'label': 'concept proposal'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_update_stage_label_order_and_active_status(self):
        stage = DefenseStage.objects.get(label='Final Defense')

        response = self.client.patch(
            f'/api/defense-stages/{stage.id}/',
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

        read_response = self.client.get('/api/defense-stages/')
        create_response = self.client.post(
            '/api/defense-stages/',
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
