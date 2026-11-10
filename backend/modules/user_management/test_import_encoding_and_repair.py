from unittest.mock import patch
from django.contrib.auth import get_user_model
from django.test import SimpleTestCase
from rest_framework.test import APITestCase
from authentication_access_control.models import SystemAuditLog
from student_teams.bulk_import import _person_names
from student_teams.person_names import PersonNameIndex
from types import SimpleNamespace
from user_management.serializers import (ManagedUserSerializer, BulkUserRowSerializer,
    OfficialClassListStudentSerializer)
from user_management.academic_records.serializers import (StudentAcademicRecordWriteSerializer,
    RolloverActionSerializer)


def person(username, first, last, active=True):
    return SimpleNamespace(username=username, first_name=first, last_name=last,
        role='student', is_active=active)


class FinalNameMatchingTests(SimpleTestCase):
    def test_all_name_write_boundaries_reject_controls_before_trimming(self):
        for serializer in (ManagedUserSerializer, BulkUserRowSerializer,
                           OfficialClassListStudentSerializer, StudentAcademicRecordWriteSerializer,
                           RolloverActionSerializer):
            for field in ('first_name', 'last_name', 'full_name'):
                if field not in serializer().fields:
                    continue
                for bad in ('\u000bName', 'Name\ufffd'):
                    with self.subTest(serializer=serializer, field=field, bad=bad):
                        value = serializer(data={field: bad})
                        self.assertFalse(value.is_valid())
                        self.assertIn('encoding problem', str(value.errors[field]))

    def test_known_surname_period_and_full_middle_initial_resolve(self):
        users = [person('pauyon', 'LENYVIE T', 'PAUYON'), person('catada', 'MERNEL ANTIO', 'CATADA')]
        index = PersonNameIndex(users, _person_names)
        for raw, username, kind in (
            ('PAUYON. Lenyvie T.', 'pauyon', 'surname_separator'),
            ('CATADA, Mernel A.', 'catada', 'middle_initial_expanded'),
        ):
            with self.subTest(raw=raw):
                result = index.resolve(raw, 'student')
                self.assertEqual(result.user.username, username)
                self.assertEqual(result.kind, kind)

    def test_expanded_name_duplicates_and_inactive_accounts_remain_ambiguous(self):
        for other in (person('b', 'Mernel Andres', 'Catada'),
                      person('b', 'Mernel A', 'Catada', active=False),
                      person('b', 'Mernel', 'Catada')):
            index = PersonNameIndex([person('a', 'Mernel Antio', 'Catada'), other], _person_names)
            self.assertEqual(index.resolve('CATADA, Mernel A.', 'student').status, 'ambiguous')

    def test_conflicts_suffixes_surname_variants_and_missing_users_need_review(self):
        index = PersonNameIndex([person('n', 'Noel Jr. R', 'Dominguez'),
            person('l', 'Maxel Mae B', 'Lapera'), person('j', 'Janice', 'Ocampo')], _person_names)
        for raw, kind in (('DOMINGUEZ, Noel R.', 'suffix_difference'),
                          ('LAPERA, Maxel Mae P.', 'middle_initial_conflict'),
                          ('Janice Ruiz - Ocampo', 'surname_variant')):
            result = index.resolve(raw, 'student')
            self.assertIsNone(result.user)
            self.assertEqual(result.kind, kind)
        self.assertEqual(index.resolve('Not Registered Person', 'student').status, 'not_found')

    def test_replacement_character_never_name_matches_but_registered_id_remains_usable(self):
        user = person('213', 'Ray An', 'QUI\ufffdON')
        index = PersonNameIndex([user], _person_names)
        self.assertEqual(index.resolve('QUI\ufffdON, Ray An', 'student').status, 'encoding_problem')
        self.assertEqual(index.resolve('QUI\u00d1ON, Ray An J.', 'student').status, 'encoding_problem')
        self.assertIs(index.resolve('213', 'student').user, user)
        clean = PersonNameIndex([person('a', 'Ray An', 'QUI\u00d1ON')], _person_names)
        self.assertIsNone(clean.resolve('QUINON, Ray An', 'student').user)


class NameRepairApiTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.admin = User.objects.create_user(username='repair-admin', role='admin')
        self.faculty = User.objects.create_user(username='213', role='faculty',
            first_name='RAY AN', last_name='QUI\ufffdON', email='keep@example.com', is_adviser=True)
        self.client.force_authenticate(self.admin)

    def preview(self, **changes):
        return self.client.post('/api/users/name-repair/preview/', {
            'username': '213', 'expected_role': 'faculty', 'first_name': 'RAY AN',
            'last_name': 'QUI\u00d1ON', 'source_filename': 'official-faculty.csv', **changes}, format='json')

    def apply(self, token):
        return self.client.post('/api/users/name-repair/apply/', {'preview_token': token}, format='json')

    def test_review_then_apply_preserves_all_non_name_fields(self):
        before = get_user_model().objects.filter(pk=self.faculty.pk).values().get()
        response = self.preview()
        self.assertEqual(response.status_code, 200, response.data)
        self.faculty.refresh_from_db()
        self.assertEqual(self.faculty.last_name, 'QUI\ufffdON')
        self.assertFalse(SystemAuditLog.objects.filter(action='user.name_repair').exists())
        result = self.apply(response.data['preview_token'])
        self.assertEqual(result.status_code, 200, result.data)
        after = get_user_model().objects.filter(pk=self.faculty.pk).values().get()
        changed = {key for key in before if before[key] != after[key]}
        self.assertEqual(changed, {'last_name'})
        self.assertEqual(after['last_name'], 'QUI\u00d1ON')
        self.assertTrue(SystemAuditLog.objects.filter(action='user.name_repair').exists())

    def test_stale_wrong_role_extra_fields_and_unauthorized_reviews_fail(self):
        self.assertEqual(self.preview(expected_role='student').status_code, 400)
        self.assertEqual(self.preview(password='do-not-use').status_code, 400)
        token = self.preview().data['preview_token']
        self.faculty.first_name = 'Changed Elsewhere'
        self.faculty.save(update_fields=['first_name'])
        self.assertEqual(self.apply(token).status_code, 409)
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.preview().status_code, 403)

    def test_audit_failure_rolls_back_and_tokens_cannot_be_modified(self):
        token = self.preview().data['preview_token']
        self.assertEqual(self.apply(token + 'x').status_code, 400)
        with patch('user_management.name_repairs.log_high_impact_action', side_effect=RuntimeError('audit unavailable')):
            with self.assertRaises(RuntimeError):
                self.apply(token)
        self.faculty.refresh_from_db()
        self.assertEqual(self.faculty.last_name, 'QUI\ufffdON')

    def test_review_is_bound_to_actor_and_expires(self):
        token = self.preview().data['preview_token']
        other = get_user_model().objects.create_user(username='other-admin', role='admin')
        self.client.force_authenticate(other)
        self.assertEqual(self.apply(token).status_code, 400)
        self.client.force_authenticate(self.admin)
        from django.core import signing
        with patch('user_management.name_repairs.signing.loads', side_effect=signing.SignatureExpired):
            self.assertEqual(self.apply(token).status_code, 400)
        self.faculty.refresh_from_db()
        self.assertEqual(self.faculty.last_name, 'QUI\ufffdON')

    def test_unicode_faculty_import_and_api_options_preserve_enye(self):
        result = self.client.post('/api/users/bulk-import/', {'users': [{
            'id_number': 'unicode-faculty', 'first_name': 'RAY AN',
            'last_name': 'QUI\u00d1ON', 'role': 'faculty'}]}, format='json')
        self.assertIn(result.status_code, (200, 201, 207), result.data)
        self.assertFalse(result.data.get('errors'), result.data)
        user = get_user_model().objects.get(username='unicode-faculty')
        self.assertEqual(user.last_name, 'QUI\u00d1ON')
        result = self.client.get(f'/api/users/{user.pk}/')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['user']['last_name'], 'QUI\u00d1ON')

    def test_direct_user_api_cannot_store_damaged_names(self):
        result = self.client.patch(f'/api/users/{self.faculty.pk}/',
            {'last_name': 'BROKEN\ufffd'}, format='json')
        self.assertEqual(result.status_code, 400)
        result = self.client.post('/api/users/bulk-import/', {'users': [{
            'id_number': 'bad-faculty', 'first_name': 'Broken', 'last_name': '\ufffd',
            'role': 'faculty'}]}, format='json')
        self.assertIn(result.status_code, (200, 207, 400))
        self.assertTrue(result.data.get('errors'))
        self.assertFalse(get_user_model().objects.filter(username='bad-faculty').exists())
