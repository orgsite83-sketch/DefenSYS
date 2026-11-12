from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from academic_period_management.models import SchoolYear, Semester
from .models import DefenseSchedule

User = get_user_model()


class ScheduleReferenceTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='reference-admin', role='admin')
        self.faculty = User.objects.create_user(username='213', role='faculty',
            first_name='Mernel Antio', last_name='Catada')
        year = SchoolYear.objects.create(label='2090-2091')
        Semester.objects.filter(is_active=True).update(is_active=False)
        self.term = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.client.force_authenticate(self.admin)

    def preview(self, text='MERNEL A. CATADA', **changes):
        ref = {'reference_id': 'file:6:chair', 'duty': 'chair', 'text': text, **changes.pop('ref', {})}
        return self.client.post('/api/defense/schedules/import-reference-preview/', {
            'scope': 'capstone', 'semester_id': self.term.pk, 'revision': 'r1',
            'references': [ref], **changes}, format='json')

    def test_shared_initial_expansion_and_read_only_preview(self):
        response = self.preview()
        self.assertEqual(response.status_code, 200, response.data)
        ref = response.data['references'][0]
        self.assertEqual(ref['account']['id'], self.faculty.pk)
        self.assertEqual(ref['review_state'], 'matched')
        self.faculty.refresh_from_db()
        self.assertFalse(self.faculty.is_panelist)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_inactive_duplicate_blocks_automatic_assignment(self):
        User.objects.create_user(username='inactive-213', role='faculty',
            first_name='Mernel A.', last_name='Catada', is_active=False)
        response = self.preview()
        ref = response.data['references'][0]
        self.assertEqual(ref['review_state'], 'needs_confirmation')
        self.assertIsNone(ref['account'])
        self.assertTrue(all(c['is_active'] for c in ref['candidates']))

    def test_typo_is_only_a_suggestion_and_explicit_id_is_retained(self):
        response = self.preview('Mernel Antoi Catada')
        self.assertIsNone(response.data['references'][0]['account'])
        chosen = self.preview('Mernel Antoi Catada', ref={'selected_account_id': self.faculty.pk})
        self.assertEqual(chosen.data['references'][0]['account']['id'], self.faculty.pk)

    def test_encoding_and_id_selection(self):
        self.assertEqual(self.preview('Mernel Catad\ufffd').data['references'][0]['review_state'], 'encoding_problem')
        self.faculty.last_name = 'Catad\ufffd'
        self.faculty.save(update_fields=['last_name'])
        ref = self.preview('213').data['references'][0]
        self.assertEqual(ref['account']['id'], self.faculty.pk)
        self.assertIn('needs repair', ref['name_warning'])

    def test_inactive_wrong_role_and_unknown_ids_are_not_assignable(self):
        student = User.objects.create_user(username='reference-student', role='student')
        for pk in (student.pk, 999999):
            self.assertIsNone(self.preview(ref={'selected_account_id': pk}).data['references'][0]['account'])
        self.faculty.is_active = False
        self.faculty.save(update_fields=['is_active'])
        self.assertEqual(self.preview('213').data['references'][0]['review_state'], 'eligibility_issue')

    def test_permission_scope_term_and_duplicate_request_guards(self):
        self.assertEqual(self.preview(semester_id=999999).status_code, 400)
        self.assertEqual(self.preview(references=[{'reference_id': 'x', 'duty': 'bad', 'text': '213'}]).status_code, 400)
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.preview().status_code, 403)
        lead = User.objects.create_user(username='reference-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        self.client.force_authenticate(lead)
        self.assertEqual(self.preview().status_code, 403)
        ref = self.preview('213', scope='pit').data['references'][0]
        self.assertEqual(ref['review_state'], 'eligibility_issue')
        self.assertIsNotNone(ref['account'])
        self.assertEqual(self.preview(scope='pit', ref={'duty': 'documenter'}).status_code, 400)

    def test_repeated_references_use_bounded_queries_without_any_writes(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        references = [{'reference_id': f'file:{i}:chair', 'duty': 'chair', 'text': 'MERNEL A. CATADA'} for i in range(100)]
        with CaptureQueriesContext(connection) as queries:
            response = self.preview(references=references)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data['references']), 100)
        self.assertLessEqual(len(queries), 5)
        self.assertFalse(any(q['sql'].lstrip().upper().startswith(('UPDATE ', 'INSERT ', 'DELETE ')) for q in queries))

    def test_conflicting_details_require_selection_and_context_is_validated(self):
        self.faculty.last_name = 'Catada Jr.'
        self.faculty.save(update_fields=['last_name'])
        ref = self.preview().data['references'][0]
        self.assertEqual(ref['review_state'], 'needs_confirmation')
        self.assertIsNone(ref['account'])
        self.assertEqual(self.preview(defense_stage_id=999999).status_code, 400)
        duplicate = {'reference_id': 'same', 'duty': 'chair', 'text': '213'}
        self.assertEqual(self.preview(references=[duplicate, duplicate]).status_code, 400)
