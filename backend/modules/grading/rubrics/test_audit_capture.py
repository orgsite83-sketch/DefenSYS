from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from .models import Rubric


class RubricAuditCaptureTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='rubric-audit-admin', role='admin')
        self.client.force_authenticate(self.admin)
        year, _ = SchoolYear.objects.get_or_create(label='2026-2027')
        self.semester, _ = Semester.objects.get_or_create(school_year=year, label=Semester.FIRST)
        self.payload = {
            'name': 'Evidence rubric', 'scope': 'capstone', 'semester_id': self.semester.pk,
            'evaluation_type': 'panel', 'scale': Rubric.SCALE_10,
            'criteria': [{'name': 'Original criterion', 'max_score': 10, 'weight': 100}],
        }

    def create_rubric(self):
        response = self.client.post('/api/grading/rubrics/', self.payload, format='json')
        self.assertEqual(response.status_code, 201)
        return Rubric.objects.get(pk=response.data['rubric']['id'])

    def test_creation_records_criteria_without_requesting_a_reason(self):
        rubric = self.create_rubric()
        log = SystemAuditLog.objects.get(action='rubric.create', target_id=str(rubric.pk))
        self.assertEqual(log.review_status, 'captured')
        self.assertEqual(log.new_values['criteria'][0]['name'], 'Original criterion')

    def test_criterion_only_edit_records_before_and_after_with_supplied_reason(self):
        rubric = self.create_rubric()
        payload = {**self.payload, 'criteria': [{'name': 'Revised criterion', 'max_score': 10, 'weight': 100}], 'reason': 'Corrected criterion wording.'}
        response = self.client.patch(f'/api/grading/rubrics/{rubric.pk}/', payload, format='json')
        self.assertEqual(response.status_code, 200)
        log = SystemAuditLog.objects.get(action='rubric.update')
        self.assertEqual(log.old_values['criteria'][0]['name'], 'Original criterion')
        self.assertEqual(log.new_values['criteria'][0]['name'], 'Revised criterion')
        self.assertEqual(log.reason, payload['reason'])
        self.assertEqual(log.review_status, 'captured')

    def test_audit_failure_rolls_back_creation_edit_delete_and_publish(self):
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('Audit unavailable')):
            response = self.client.post('/api/grading/rubrics/', self.payload, format='json')
        self.assertEqual(response.status_code, 500)
        self.assertFalse(Rubric.objects.filter(name=self.payload['name']).exists())
        rubric = self.create_rubric()
        original_id = rubric.pk
        for method, path, data in (
            ('patch', f'/api/grading/rubrics/{original_id}/', {**self.payload, 'name': 'Changed name'}),
            ('post', f'/api/grading/rubrics/{original_id}/publish/', {}),
            ('delete', f'/api/grading/rubrics/{original_id}/', {}),
        ):
            with self.subTest(method=method):
                with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('Audit unavailable')):
                    response = getattr(self.client, method)(path, data, format='json')
                self.assertEqual(response.status_code, 500)
                rubric.refresh_from_db()
                self.assertEqual(rubric.name, self.payload['name'])
                self.assertEqual(rubric.status, Rubric.STATUS_DRAFT)
                self.assertEqual(rubric.criteria.get().name, 'Original criterion')
                self.assertEqual(SystemAuditLog.objects.count(), 1)

