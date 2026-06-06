from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
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
        response = self.client.get('/api/grading/rubrics/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester']['id'], self.semester.id)
        self.assertIn('5-Point Scale', response.data['scale_options'])
        self.assertEqual(response.data['counts']['all'], 0)
        self.assertIn(
            'Project Proposal',
            [stage['label'] for stage in response.data['defense_stages']],
        )

    def test_admin_can_create_draft_rubric_with_criteria(self):
        response = self.client.post('/api/grading/rubrics/', self.rubric_payload(), format='json')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['rubric']['status'], Rubric.STATUS_DRAFT)
        self.assertEqual(response.data['rubric']['criteria_count'], 2)
        self.assertEqual(Rubric.objects.get().criteria.count(), 2)

    def test_create_rubric_requires_scope(self):
        payload = self.rubric_payload()
        payload.pop('scope')

        response = self.client.post('/api/grading/rubrics/', payload, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertIn('scope', response.data)
        self.assertEqual(Rubric.objects.count(), 0)

    def test_pit_adviser_rubric_is_rejected(self):
        self.client.force_authenticate(user=self._pit_lead_user('pit-lead-adviser'))
        response = self.client.post(
            '/api/grading/rubrics/',
            self.rubric_payload(
                name='PIT Adviser Rubric',
                scope=Rubric.SCOPE_PIT,
                defense_stage_id=None,
                evaluation_type=Rubric.EVAL_ADVISER,
            ),
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('evaluation_type', response.data)
        self.client.force_authenticate(user=self.admin)

    def test_publish_locks_rubric(self):
        create = self.client.post('/api/grading/rubrics/', self.rubric_payload(), format='json')
        rubric_id = create.data['rubric']['id']

        response = self.client.post(f'/api/grading/rubrics/{rubric_id}/publish/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rubric']['status'], Rubric.STATUS_PUBLISHED)
        self.assertTrue(response.data['rubric']['is_locked'])

    def test_capstone_weight_patch_is_rejected_use_stage_config(self):
        create = self.client.post('/api/grading/rubrics/', self.rubric_payload(), format='json')
        rubric_id = create.data['rubric']['id']

        response = self.client.patch(
            f'/api/grading/rubrics/{rubric_id}/weights/',
            {'panel_weight': 60, 'adviser_weight': 20, 'peer_weight': 20},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('defense stage', response.data['detail'].lower())

    def test_capstone_rubric_reflects_stage_grading_config(self):
        self.client.patch(
            f'/api/defense/stages/{self.stage.id}/grading-config/?semester_id={self.semester.id}',
            {'panel_weight': 55, 'adviser_weight': 25, 'peer_weight': 20},
            format='json',
        )
        create = self.client.post('/api/grading/rubrics/', self.rubric_payload(), format='json')

        self.assertEqual(create.status_code, 201)
        self.assertEqual(create.data['rubric']['weights']['panel'], 55)
        self.assertEqual(create.data['rubric']['weights']['adviser'], 25)

    def pit_rubric_payload(self, **overrides):
        payload = self.rubric_payload(
            scope=Rubric.SCOPE_PIT,
            defense_stage_id=None,
            event_name='',
            evaluation_type=Rubric.EVAL_PANEL,
        )
        payload.update({'name': 'PIT Panel Rubric', **overrides})
        return payload

    def _pit_lead_user(self, username='pit-lead-rubric'):
        return User.objects.create_user(
            username=username,
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )

    def test_admin_list_options_scopes_capstone_only(self):
        response = self.client.get('/api/grading/rubrics/')

        self.assertEqual(response.status_code, 200)
        scope_values = [item['value'] for item in response.data['scopes']]
        self.assertEqual(scope_values, [Rubric.SCOPE_CAPSTONE])

    def test_admin_cannot_create_pit_rubric(self):
        response = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('scope', response.data)

    def test_admin_can_list_pit_rubrics(self):
        pit_lead = self._pit_lead_user('pit-lead-list')
        self.client.force_authenticate(user=pit_lead)
        self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(name='Listed PIT Rubric'),
            format='json',
        )

        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/grading/rubrics/?scope=pit')

        self.assertEqual(response.status_code, 200)
        names = [r['name'] for r in response.data['rubrics']]
        self.assertIn('Listed PIT Rubric', names)

    def test_pit_rubric_without_event_name_is_valid(self):
        self.client.force_authenticate(user=self._pit_lead_user('pit-lead-create'))
        response = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        rubric = Rubric.objects.get()
        self.assertEqual(rubric.scope, Rubric.SCOPE_PIT)
        self.assertEqual(rubric.event_name, '')

    def test_pit_rubric_stores_criteria_only_no_grade_split(self):
        self.client.force_authenticate(user=self._pit_lead_user('pit-lead-weights'))
        create = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(panel_weight=70, peer_weight=30),
            format='json',
        )
        self.assertEqual(create.status_code, 201)
        self.assertIsNone(create.data['rubric']['weights'])
        rubric = Rubric.objects.get()
        self.assertEqual(rubric.panel_weight, 0)
        self.assertEqual(rubric.peer_weight, 0)

    def test_pit_rubric_weight_patch_rejected_use_scheduler(self):
        self.client.force_authenticate(user=self._pit_lead_user('pit-lead-patch'))
        create = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(),
            format='json',
        )
        rubric_id = create.data['rubric']['id']

        response = self.client.patch(
            f'/api/grading/rubrics/{rubric_id}/weights/',
            {'panel_weight': 75, 'peer_weight': 25},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('Defense Scheduler', response.data['detail'])

    def test_pit_lead_sees_only_own_rubrics(self):
        pit_a = User.objects.create_user(
            username='pit-lead-a',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        pit_b = User.objects.create_user(
            username='pit-lead-b',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )

        self.client.force_authenticate(user=pit_a)
        create = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(name='PIT Rubric A'),
            format='json',
        )
        self.assertEqual(create.status_code, 201)

        list_a = self.client.get('/api/grading/rubrics/')
        self.assertEqual(list_a.status_code, 200)
        self.assertEqual(len(list_a.data['rubrics']), 1)
        self.assertEqual(list_a.data['rubrics'][0]['name'], 'PIT Rubric A')

        self.client.force_authenticate(user=pit_b)
        list_b = self.client.get('/api/grading/rubrics/')
        self.assertEqual(list_b.status_code, 200)
        self.assertEqual(len(list_b.data['rubrics']), 0)

        self.client.force_authenticate(user=self.admin)
        list_admin = self.client.get('/api/grading/rubrics/')
        self.assertEqual(list_admin.status_code, 200)
        self.assertGreaterEqual(len(list_admin.data['rubrics']), 1)

    def test_pit_lead_cannot_mutate_another_pit_leads_rubric(self):
        pit_a = User.objects.create_user(
            username='pit-lead-a2',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        pit_b = User.objects.create_user(
            username='pit-lead-b2',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )

        self.client.force_authenticate(user=pit_a)
        create = self.client.post(
            '/api/grading/rubrics/',
            self.pit_rubric_payload(name='Owned By A'),
            format='json',
        )
        rubric_id = create.data['rubric']['id']

        self.client.force_authenticate(user=pit_b)
        patch = self.client.patch(
            f'/api/grading/rubrics/{rubric_id}/',
            {'name': 'Hijacked'},
            format='json',
        )
        delete = self.client.delete(f'/api/grading/rubrics/{rubric_id}/')
        publish = self.client.post(f'/api/grading/rubrics/{rubric_id}/publish/')

        self.assertEqual(patch.status_code, 404)
        self.assertEqual(delete.status_code, 404)
        self.assertEqual(publish.status_code, 404)

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
