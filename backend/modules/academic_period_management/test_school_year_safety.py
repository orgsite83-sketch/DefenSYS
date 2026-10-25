from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from rest_framework.exceptions import APIException
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from .models import SchoolYear, Semester
from .serializers import SchoolYearUpdateSerializer


class SchoolYearSafetyTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='year-safety-admin', role='admin')
        self.client.force_authenticate(self.admin)
        self.year = SchoolYear.objects.create(label='2025-2026')
        self.url = f'/api/academic-periods/{self.year.pk}/'

    def test_unused_year_can_be_renamed_with_audit(self):
        response = self.client.patch(self.url, {'school_year': '2026-2027'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.year.refresh_from_db()
        self.assertEqual(self.year.label, '2026-2027')
        audit = SystemAuditLog.objects.get(action='school_year.renamed')
        self.assertEqual(audit.actor_id, self.admin.pk)
        self.assertEqual(audit.old_values, {'label': '2025-2026'})
        self.assertEqual(audit.new_values, {'label': '2026-2027'})

    def test_year_with_even_an_empty_semester_cannot_be_renamed(self):
        term = Semester.objects.create(school_year=self.year, label=Semester.SECOND)
        response = self.client.patch(self.url, {'school_year': '2026-2027'}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('locked', str(response.data))
        self.year.refresh_from_db()
        term.refresh_from_db()
        self.assertEqual(self.year.label, '2025-2026')
        self.assertEqual(term.school_year_id, self.year.pk)
        self.assertFalse(SystemAuditLog.objects.filter(action='school_year.renamed').exists())

    def test_model_and_admin_validation_enforce_the_same_rule(self):
        Semester.objects.create(school_year=self.year, label=Semester.FIRST)
        self.year.label = '2026-2027'
        with self.assertRaises(ValidationError):
            self.year.clean()
        with self.assertRaises(ValidationError):
            self.year.save(update_fields=['label'])

    def test_stale_prefetched_empty_year_does_not_bypass_save_guard(self):
        stale = SchoolYear.objects.prefetch_related('semesters').get(pk=self.year.pk)
        serializer = SchoolYearUpdateSerializer(instance=stale, data={'school_year': '2026-2027'})
        self.assertTrue(serializer.is_valid())
        Semester.objects.create(school_year=self.year, label=Semester.FIRST)
        from rest_framework.exceptions import ValidationError as ApiValidationError
        with self.assertRaises(ApiValidationError):
            serializer.save()
        self.year.refresh_from_db()
        self.assertEqual(self.year.label, '2025-2026')

    def test_noop_is_allowed_for_used_year_and_does_not_write_audit(self):
        Semester.objects.create(school_year=self.year, label=Semester.FIRST)
        response = self.client.patch(self.url, {'school_year': self.year.label}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['school_year']['can_edit_label'])
        self.assertIn('locked', response.data['school_year']['edit_lock_reason'])
        self.assertFalse(SystemAuditLog.objects.filter(action='school_year.renamed').exists())

    def test_failed_audit_rolls_back_rename(self):
        with patch('authentication_access_control.audit.log_high_impact_action', side_effect=APIException('Audit unavailable')):
            response = self.client.patch(self.url, {'school_year': '2026-2027'}, format='json')
        self.assertEqual(response.status_code, 500)
        self.year.refresh_from_db()
        self.assertEqual(self.year.label, '2025-2026')
