from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense_stages.models import DefenseStage
from .models import Rubric


User = get_user_model()


class RubricEngineApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
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
        self.stage = DefenseStage.objects.get(label='Project Proposal')
        self.client.force_authenticate(user=self.admin)

    def rubric_payload(self, **overrides):
        payload = {
            'name': 'Project Proposal Panel Rubric',
            'scope': Rubric.SCOPE_CAPSTONE,
            'semester_id': self.semester.id,
            'defense_stage_id': self.stage.id,
            'evaluation_type': Rubric.EVAL_PANEL,
            'scale': Rubric.SCALE_10,
            'status': Rubric.STATUS_DRAFT,
            'criteria': [
                {
                    'name': 'Technical Feasibility',
                    'description': 'Feasibility of the proposed solution.',
                    'scale': Rubric.SCALE_10,
                    'max_score': 10,
                    'weight': 1,
                    'display_order': 0,
                },
                {
                    'name': 'Presentation',
                    'scale': Rubric.SCALE_10,
                    'max_score': 10,
                    'weight': 1,
                    'display_order': 1,
                },
            ],
        }
        payload.update(overrides)
        return payload

    def test_list_returns_options_and_active_semester(self):
        response = self.client.get('/api/rubrics/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester']['id'], self.semester.id)
        self.assertIn('5-Point Scale', response.data['scale_options'])
        self.assertEqual(response.data['counts']['all'], 0)
        self.assertIn(
            'Project Proposal',
            [stage['label'] for stage in response.data['defense_stages']],
        )

    def test_admin_can_create_draft_rubric_with_criteria(self):
        response = self.client.post('/api/rubrics/', self.rubric_payload(), format='json')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['rubric']['status'], Rubric.STATUS_DRAFT)
        self.assertEqual(response.data['rubric']['criteria_count'], 2)
        self.assertEqual(Rubric.objects.get().criteria.count(), 2)

    def test_pit_adviser_rubric_is_rejected(self):
        response = self.client.post(
            '/api/rubrics/',
            self.rubric_payload(
                name='PIT Adviser Rubric',
                scope=Rubric.SCOPE_PIT,
                defense_stage_id=None,
                event_name='1st Year PIT Demo',
                evaluation_type=Rubric.EVAL_ADVISER,
            ),
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('evaluation_type', response.data)

    def test_publish_locks_rubric(self):
        create = self.client.post('/api/rubrics/', self.rubric_payload(), format='json')
        rubric_id = create.data['rubric']['id']

        response = self.client.post(f'/api/rubrics/{rubric_id}/publish/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rubric']['status'], Rubric.STATUS_PUBLISHED)
        self.assertTrue(response.data['rubric']['is_locked'])

    def test_weight_update_requires_total_100(self):
        create = self.client.post('/api/rubrics/', self.rubric_payload(), format='json')
        rubric_id = create.data['rubric']['id']

        bad_response = self.client.patch(
            f'/api/rubrics/{rubric_id}/weights/',
            {'panel_weight': 60, 'adviser_weight': 30, 'peer_weight': 30},
            format='json',
        )
        good_response = self.client.patch(
            f'/api/rubrics/{rubric_id}/weights/',
            {'panel_weight': 60, 'adviser_weight': 20, 'peer_weight': 20},
            format='json',
        )

        self.assertEqual(bad_response.status_code, 400)
        self.assertEqual(good_response.status_code, 200)
        self.assertEqual(good_response.data['rubric']['weights']['panel'], 60)

    @override_settings(ENABLE_PROTOTYPE_TOOLS=True)
    def test_demo_seed_creates_six_published_capstone_rubrics(self):
        response = self.client.post('/api/rubrics/seed-demo/')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 6)
        self.assertEqual(Rubric.objects.filter(status=Rubric.STATUS_PUBLISHED).count(), 6)
        self.assertEqual(Rubric.objects.filter(evaluation_type=Rubric.EVAL_PEER).count(), 2)

    def test_admin_dashboard_counts_published_rubrics_and_phase_eight(self):
        for index in range(6):
            Rubric.objects.create(
                name=f'Published Rubric {index + 1}',
                scope=Rubric.SCOPE_CAPSTONE,
                semester=self.semester,
                defense_stage=self.stage,
                evaluation_type=Rubric.EVAL_PANEL,
                status=Rubric.STATUS_PUBLISHED,
                created_by=self.admin,
            )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['published_rubrics'], 6)
        self.assertEqual(response.data['migration']['phase'], 15)
