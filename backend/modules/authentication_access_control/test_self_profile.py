import tempfile
from types import SimpleNamespace
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

User = get_user_model()


class SelfProfileTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='profile-student', password='ProfileTest!29', role='student',
            email='original@example.com', phone_number='09171234567',
        )
        self.client.force_authenticate(self.user)
        self.password_hash = self.user.password

    def update_contacts(self, **values):
        return self.client.patch('/api/me/', {
            'current_password': 'ProfileTest!29', **values,
        }, format='json')

    def test_updates_only_own_contacts_and_preserves_credentials(self):
        other = User.objects.create_user(username='other-profile', password='OtherTest!29')
        response = self.update_contacts(email=' new@gmail.com ', phone_number='+63 (917) 111-2233')
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        other.refresh_from_db()
        self.assertEqual(self.user.email, 'new@gmail.com')
        self.assertEqual(self.user.phone_number, '+639171112233')
        self.assertEqual(self.user.password, self.password_hash)
        self.assertEqual(other.email, '')
        self.assertNotIn('current_password', response.data)
        self.assertNotIn('password', response.data)
        refreshed = self.client.get('/api/me/')
        self.assertEqual(refreshed.data['email'], 'new@gmail.com')

    def test_null_and_whitespace_contacts_clear_without_literal_placeholders(self):
        for values in ({'email': None, 'phone_number': '   '}, {'email': ' ', 'phone_number': None}):
            with self.subTest(values=values):
                response = self.update_contacts(**values)
                self.assertEqual(response.status_code, 200)
                self.user.refresh_from_db()
                self.assertEqual((self.user.email, self.user.phone_number), ('', ''))
                self.assertEqual(self.user.password, self.password_hash)

    def test_preserves_leading_zero_and_omitted_contact(self):
        response = self.update_contacts(phone_number='09170000000')
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.phone_number, '09170000000')
        self.assertEqual(self.user.email, 'original@example.com')

    def test_invalid_contacts_are_atomic(self):
        for values in ({'email': 'invalid', 'phone_number': '09170000000'},
                       {'email': 'new@example.com', 'phone_number': 'not-a-phone'}):
            with self.subTest(values=values):
                self.assertEqual(self.update_contacts(**values).status_code, 400)
                self.user.refresh_from_db()
                self.assertEqual(self.user.email, 'original@example.com')
                self.assertEqual(self.user.phone_number, '09171234567')

    def test_missing_or_wrong_password_does_not_save(self):
        for password in (None, 'incorrect'):
            body = {'email': 'new@example.com'}
            if password is not None:
                body['current_password'] = password
            response = self.client.patch('/api/me/', body, format='json')
            self.assertEqual(response.status_code, 400)
            self.assertIn('current_password', response.data)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, 'original@example.com')

    def test_rejects_identity_role_team_and_password_payloads(self):
        protected = {
            'id': 123, 'username': 'replacement', 'first_name': 'Renamed',
            'last_name': 'Renamed', 'role': 'admin', 'is_staff': True,
            'is_superuser': True, 'is_panelist': True, 'is_pit_lead': True,
            'pit_lead_year': '1st Year', 'is_adviser': True, 'is_documenter': True,
            'is_uploader': True, 'team_id': '123', 'team_name': 'Replacement',
            'password': 'Replacement!29', 'user_id': 123,
        }
        for field, value in protected.items():
            with self.subTest(field=field):
                response = self.update_contacts(email='new@example.com', **{field: value})
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.data)
        self.user.refresh_from_db()
        self.assertEqual(self.user.role, 'student')
        self.assertEqual(self.user.email, 'original@example.com')
        self.assertEqual(self.user.password, self.password_hash)

    def test_media_uploads_and_removal_do_not_require_contact_password(self):
        gif = (b'GIF89a\x01\x00\x01\x00\x00\x00\x00!\xf9\x04'
               b'\x01\x0a\x00\x01\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02'
               b'\x02L\x01\x00;')
        with tempfile.TemporaryDirectory() as directory, override_settings(MEDIA_ROOT=directory):
            for field in ('avatar', 'e_signature'):
                with self.subTest(field=field):
                    image = SimpleUploadedFile('profile.png', gif, content_type='image/png')
                    response = self.client.patch('/api/me/', {field: image}, format='multipart')
                    self.assertEqual(response.status_code, 200)
                    self.user.refresh_from_db()
                    self.assertTrue(getattr(self.user, field))
                    response = self.client.patch('/api/me/', {f'remove_{field}': 'true'}, format='json')
                    self.assertEqual(response.status_code, 200)
                    self.user.refresh_from_db()
                    self.assertFalse(getattr(self.user, field))

    def test_invalid_contact_request_cannot_remove_avatar(self):
        self.user.avatar = 'avatars/existing.png'
        self.user.save(update_fields=['avatar'])
        response = self.update_contacts(email='invalid', remove_avatar='true')
        self.assertEqual(response.status_code, 400)
        self.user.refresh_from_db()
        self.assertEqual(self.user.avatar.name, 'avatars/existing.png')

    def test_team_name_and_id_share_one_current_membership_resolution(self):
        with patch('student_teams.current_identity.current_team_for_student',
                   return_value=SimpleNamespace(pk=47, name='Team Atlas')) as resolve:
            response = self.client.get('/api/me/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['team_id'], '47')
        self.assertEqual(response.data['team_name'], 'Team Atlas')
        resolve.assert_called_once()

    def test_unassigned_and_unnamed_teams(self):
        for team, expected_id, expected_name in ((None, None, None),
                (SimpleNamespace(pk=47, name=''), '47', '')):
            with patch('student_teams.current_identity.current_team_for_student', return_value=team):
                response = self.client.get('/api/me/')
            self.assertEqual(response.data['team_id'], expected_id)
            self.assertEqual(response.data['team_name'], expected_name)

    def test_overlapping_memberships_remain_an_error(self):
        with patch('student_teams.current_identity.current_team_for_student',
                   side_effect=ValidationError('Overlapping memberships')):
            self.assertEqual(self.client.get('/api/me/').status_code, 400)

    def test_authentication_required(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.update_contacts(email='new@example.com').status_code, 401)

    def test_non_object_payload_is_a_validation_error(self):
        response = self.client.patch('/api/me/', [{'email': 'new@example.com'}], format='json')
        self.assertEqual(response.status_code, 400)

    def test_invalid_image_cannot_clear_existing_media_or_save_contacts(self):
        self.user.avatar = 'avatars/existing.png'
        self.user.save(update_fields=['avatar'])
        response = self.client.patch('/api/me/', {
            'remove_avatar': 'true', 'e_signature': SimpleUploadedFile(
                'invalid.png', b'not an image', content_type='image/png'),
            'email': 'new@example.com', 'current_password': 'ProfileTest!29',
        }, format='multipart')
        self.assertEqual(response.status_code, 400)
        self.user.refresh_from_db()
        self.assertEqual(self.user.avatar.name, 'avatars/existing.png')
        self.assertEqual(self.user.email, 'original@example.com')
