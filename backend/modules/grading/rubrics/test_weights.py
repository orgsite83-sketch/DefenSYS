from decimal import Decimal
from io import StringIO
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.management import call_command
from rest_framework.test import APITestCase
from rest_framework.exceptions import APIException

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from .models import Rubric, RubricCriterion


class RubricWeightTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='weight-admin', role='admin')
        self.client.force_authenticate(self.admin)
        year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST)

    def payload(self, weights, status='draft'):
        return {
            'name': 'Weight regression rubric', 'scope': 'capstone',
            'semester_id': self.semester.pk, 'evaluation_type': 'panel',
            'status': status,
            'criteria': [
                {'name': f'Criterion {index}', 'weight': weight, 'max_score': 10, 'display_order': index}
                for index, weight in enumerate(weights)
            ],
        }

    def weights_from(self, response):
        return [Decimal(item['weight']) for item in response.data['rubric']['criteria']]

    def test_custom_percentages_survive_create_update_publish_and_reload(self):
        initial = ['40', '30', '20', '10']
        response = self.client.post('/api/grading/rubrics/', self.payload(initial), format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.weights_from(response), list(map(Decimal, initial)))
        rubric_id = response.data['rubric']['id']
        updated = ['33.33', '33.33', '23.34', '10']
        response = self.client.patch(f'/api/grading/rubrics/{rubric_id}/', self.payload(updated), format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.weights_from(response), list(map(Decimal, updated)))
        response = self.client.post(f'/api/grading/rubrics/{rubric_id}/publish/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.weights_from(response), list(map(Decimal, updated)))
        response = self.client.get(f'/api/grading/rubrics/{rubric_id}/')
        self.assertEqual(self.weights_from(response), list(map(Decimal, updated)))
        self.assertEqual(list(Rubric.objects.get(pk=rubric_id).criteria.values_list('weight', flat=True)), list(map(Decimal, updated)))

    def test_create_rejects_incomplete_and_excess_totals_for_draft_and_published(self):
        for status in ('draft', 'published'):
            for weights in ([1, 1, 1, 1], ['50', '49.99'], ['50', '50.01']):
                with self.subTest(status=status, weights=weights):
                    response = self.client.post('/api/grading/rubrics/', self.payload(weights, status), format='json')
                    self.assertEqual(response.status_code, 400)
                    self.assertIn('100%', str(response.data))
        self.assertFalse(Rubric.objects.exists())

    def test_missing_invalid_and_overprecise_weights_are_rejected(self):
        payload = self.payload([100])
        payload['criteria'][0].pop('weight')
        response = self.client.post('/api/grading/rubrics/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('weight', str(response.data))
        for weights in ([0, 100], [-1, 101], ['99.999', '0.001'], ['NaN', 100]):
            with self.subTest(weights=weights):
                response = self.client.post('/api/grading/rubrics/', self.payload(weights), format='json')
                self.assertEqual(response.status_code, 400)
        self.assertFalse(Rubric.objects.exists())

    def test_invalid_update_preserves_previous_weights(self):
        response = self.client.post('/api/grading/rubrics/', self.payload([25] * 4), format='json')
        rubric_id = response.data['rubric']['id']
        ids = list(Rubric.objects.get(pk=rubric_id).criteria.values_list('pk', flat=True))
        response = self.client.patch(f'/api/grading/rubrics/{rubric_id}/', self.payload([1] * 4), format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(list(RubricCriterion.objects.filter(rubric_id=rubric_id).values_list('pk', flat=True)), ids)
        self.assertEqual(list(RubricCriterion.objects.filter(rubric_id=rubric_id).values_list('weight', flat=True)), [Decimal(25)] * 4)

    def legacy_rubric(self, weights, status='draft'):
        rubric = Rubric.objects.create(
            name='Legacy equal weights', scope='capstone', semester=self.semester,
            evaluation_type='panel', status=status,
        )
        RubricCriterion.objects.bulk_create([
            RubricCriterion(rubric=rubric, name=f'Criterion {index}', weight=weight, display_order=index)
            for index, weight in enumerate(weights)
        ])
        return rubric

    def test_publish_rejects_legacy_invalid_total_without_changing_status(self):
        rubric = self.legacy_rubric([1] * 4)
        response = self.client.post(f'/api/grading/rubrics/{rubric.pk}/publish/')
        self.assertEqual(response.status_code, 400)
        self.assertIn('100%', str(response.data))
        rubric.refresh_from_db()
        self.assertEqual(rubric.status, 'draft')
        self.assertFalse(SystemAuditLog.objects.filter(action='rubric.publish').exists())

    def test_repair_defaults_to_preview_then_preserves_criteria_and_audits(self):
        rubric = self.legacy_rubric([1] * 4, status='published')
        ids = list(rubric.criteria.values_list('pk', flat=True))
        call_command('repair_legacy_rubric_weights', stdout=StringIO())
        self.assertEqual(list(rubric.criteria.values_list('weight', flat=True)), [Decimal(1)] * 4)
        self.assertFalse(SystemAuditLog.objects.exists())
        call_command('repair_legacy_rubric_weights', apply=True, stdout=StringIO())
        self.assertEqual(list(rubric.criteria.values_list('pk', flat=True)), ids)
        self.assertEqual(list(rubric.criteria.values_list('weight', flat=True)), [Decimal(25)] * 4)
        rubric.refresh_from_db()
        self.assertEqual(rubric.status, 'published')
        log = SystemAuditLog.objects.get(action='rubric.weights_repair')
        self.assertEqual([item['weight'] for item in log.old_values['criteria']], ['1.00'] * 4)
        self.assertEqual([item['weight'] for item in log.new_values['criteria']], ['25.00'] * 4)
        call_command('repair_legacy_rubric_weights', apply=True, stdout=StringIO())
        self.assertEqual(SystemAuditLog.objects.count(), 1)

    def test_repair_skips_custom_allocations_and_inexact_equal_percentages(self):
        custom = self.legacy_rubric([40, 30, 20, 10])
        partial = self.legacy_rubric([1, 2])
        thirds = self.legacy_rubric([1] * 3)
        call_command('repair_legacy_rubric_weights', apply=True, stdout=StringIO())
        self.assertEqual(list(custom.criteria.values_list('weight', flat=True)), list(map(Decimal, [40, 30, 20, 10])))
        self.assertEqual(list(partial.criteria.values_list('weight', flat=True)), [Decimal(1), Decimal(2)])
        self.assertEqual(list(thirds.criteria.values_list('weight', flat=True)), [Decimal(1)] * 3)
        self.assertFalse(SystemAuditLog.objects.exists())

    def test_failed_audit_rolls_back_repair(self):
        rubric = self.legacy_rubric([1] * 4)
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(APIException):
                call_command('repair_legacy_rubric_weights', apply=True, stdout=StringIO())
        self.assertEqual(list(rubric.criteria.values_list('weight', flat=True)), [Decimal(1)] * 4)
