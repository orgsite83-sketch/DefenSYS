from django.contrib.auth import get_user_model
from datetime import date, time
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense_scheduler.models import DefenseSchedule
from defense_stages.models import DefenseStage
from student_academic_records.models import StudentAcademicRecord
from student_teams.models import StudentTeam
from .models import GuestPanelistCode


User = get_user_model()


class UserManagementApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.client.force_authenticate(user=self.admin)

    def create_defense_schedule(self):
        student = User.objects.create_user(
            username='guest-student',
            password='pass12345',
            role='student',
        )
        adviser = User.objects.create_user(
            username='guest-adviser',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        stage = DefenseStage.objects.create(label='Guest Code Proposal', display_order=99)
        team = StudentTeam.objects.create(
            name='Team GuestSync',
            project_title='Guest Access Flow',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=semester,
            leader=student,
            adviser=adviser,
            ready_for_stage=stage.label,
        )
        return DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=semester,
            team=team,
            defense_stage=stage,
            scheduled_date=date(2026, 5, 15),
            start_time=time(9, 0),
            slot_duration=60,
            room='Room 401',
            created_by=self.admin,
        )

    def test_admin_can_list_users_with_counts(self):
        User.objects.create_user(username='student-1', password='pass12345', role='student')
        User.objects.create_user(username='faculty-1', password='pass12345', role='faculty')

        response = self.client.get('/api/users/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 3)
        self.assertEqual(response.data['counts']['faculty'], 2)
        self.assertEqual(response.data['counts']['students'], 1)

    def test_non_admin_cannot_manage_users(self):
        student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)

        response = self.client.get('/api/users/')

        self.assertEqual(response.status_code, 403)

    def test_create_user_defaults_password_to_username(self):
        response = self.client.post(
            '/api/users/',
            {
                'username': '2024-0001',
                'first_name': 'Juan',
                'last_name': 'Dela Cruz',
                'email': 'juan@example.com',
                'role': 'student',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        user = User.objects.get(username='2024-0001')
        self.assertTrue(user.check_password('2024-0001'))
        self.assertEqual(response.data['user']['name'], 'Juan Dela Cruz')

    def test_update_faculty_role_flags(self):
        faculty = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
        )

        response = self.client.patch(
            f'/api/users/{faculty.id}/',
            {
                'is_panelist': True,
                'is_pit_lead': True,
                'pit_lead_year': '4th Year',
                'is_repo_assistant': True,
            },
            format='json',
        )

        faculty.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(faculty.is_panelist)
        self.assertTrue(faculty.is_pit_lead)
        self.assertEqual(faculty.pit_lead_year, '4th Year')
        self.assertTrue(response.data['user']['facultyRoles']['repoAssistant'])

    def test_bulk_import_creates_new_users_and_skips_duplicates(self):
        User.objects.create_user(username='2024-0001', password='pass12345', role='student')

        response = self.client.post(
            '/api/users/bulk-import/',
            {
                'users': [
                    {
                        'id_number': '2024-0001',
                        'first_name': 'Existing',
                        'last_name': 'Student',
                        'email': 'existing@example.com',
                        'role': 'student',
                    },
                    {
                        'id_number': 'FAC-0001',
                        'first_name': 'Ada',
                        'last_name': 'Lovelace',
                        'email': 'ada@example.com',
                        'role': 'faculty',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(response.data['skipped_count'], 1)
        self.assertTrue(User.objects.get(username='FAC-0001').check_password('FAC-0001'))

    def test_bulk_import_can_create_student_academic_records(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )

        response = self.client.post(
            '/api/users/bulk-import/',
            {
                'student_context': {
                    'semester_id': semester.id,
                    'year_level': StudentAcademicRecord.FIRST_YEAR,
                },
                'users': [
                    {
                        'id_number': '2024-0003',
                        'first_name': 'Student',
                        'last_name': 'Three',
                        'email': 'student3@example.com',
                        'role': 'student',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['records_created_count'], 1)
        self.assertTrue(
            StudentAcademicRecord.objects.filter(
                student__username='2024-0003',
                semester=semester,
                year_level=StudentAcademicRecord.FIRST_YEAR,
            ).exists()
        )

    def test_admin_cannot_delete_self(self):
        response = self.client.delete(f'/api/users/{self.admin.id}/')

        self.assertEqual(response.status_code, 400)
        self.assertTrue(User.objects.filter(pk=self.admin.pk).exists())

    def test_admin_can_generate_guest_panelist_code(self):
        schedule = self.create_defense_schedule()

        response = self.client.post(
            '/api/users/guest-codes/',
            {
                'guest_name': 'Engr. Juan Dela Cruz',
                'email': 'guest@example.com',
                'defense_schedule': schedule.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(GuestPanelistCode.objects.count(), 1)
        self.assertTrue(response.data['guest_code']['code'].startswith('DEF-'))
        self.assertEqual(response.data['guest_code']['guest_name'], 'Engr. Juan Dela Cruz')
        self.assertEqual(response.data['guest_counts']['active'], 1)

    def test_admin_can_list_guest_codes_and_schedule_options(self):
        schedule = self.create_defense_schedule()
        GuestPanelistCode.objects.create(
            guest_name='External Panelist',
            defense_schedule=schedule,
            created_by=self.admin,
        )

        response = self.client.get('/api/users/guest-codes/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['guest_codes']), 1)
        self.assertEqual(len(response.data['defense_schedules']), 1)
        self.assertIn('Team GuestSync', response.data['defense_schedules'][0]['label'])

    def test_admin_can_revoke_guest_panelist_code(self):
        schedule = self.create_defense_schedule()
        guest_code = GuestPanelistCode.objects.create(
            guest_name='External Panelist',
            defense_schedule=schedule,
            created_by=self.admin,
        )

        response = self.client.patch(
            f'/api/users/guest-codes/{guest_code.id}/',
            {'is_active': False},
            format='json',
        )

        guest_code.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertFalse(guest_code.is_active)
        self.assertEqual(response.data['guest_counts']['revoked'], 1)

    def test_non_admin_cannot_manage_guest_panelist_codes(self):
        student = User.objects.create_user(
            username='student-guest-user',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)

        response = self.client.get('/api/users/guest-codes/')

        self.assertEqual(response.status_code, 403)
