from django.contrib.auth import get_user_model
from datetime import date, time
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from user_management.academic_records.models import StudentAcademicRecord
from student_teams.models import StudentTeam, TeamAdviserAssignment
from .models import FacultyRoleAssignment, GuestPanelistCode


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

    def test_update_user_clears_legacy_adviser_phase(self):
        faculty = User.objects.create_user(
            username='faculty-adv',
            password='pass12345',
            role='faculty',
            is_adviser=True,
            adviser_phase='Capstone 1',
        )

        response = self.client.patch(
            f'/api/users/{faculty.id}/',
            {'first_name': 'Updated'},
            format='json',
        )

        faculty.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(faculty.first_name, 'Updated')
        self.assertIsNone(faculty.adviser_phase)
        self.assertNotIn('adviserPhase', response.data['user']['facultyRoles'])

    def test_save_backfills_role_history_when_flag_already_on(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        faculty = User.objects.create_user(
            username='faculty-adv-existing',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )

        response = self.client.patch(
            f'/api/users/{faculty.id}/',
            {'first_name': 'Updated'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        history = FacultyRoleAssignment.objects.filter(
            user=faculty,
            role_key=FacultyRoleAssignment.ROLE_ADVISER,
        )
        self.assertEqual(history.count(), 1)
        self.assertEqual(history.first().action, FacultyRoleAssignment.ACTION_ASSIGNED)

    def test_save_does_not_duplicate_existing_assigned_history(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        faculty = User.objects.create_user(
            username='faculty-adv-dup',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        FacultyRoleAssignment.objects.create(
            user=faculty,
            role_key=FacultyRoleAssignment.ROLE_ADVISER,
            semester=semester,
            action=FacultyRoleAssignment.ACTION_ASSIGNED,
            changed_by=self.admin,
        )

        response = self.client.patch(
            f'/api/users/{faculty.id}/',
            {'first_name': 'NoDup'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            FacultyRoleAssignment.objects.filter(
                user=faculty,
                role_key=FacultyRoleAssignment.ROLE_ADVISER,
                action=FacultyRoleAssignment.ACTION_ASSIGNED,
            ).count(),
            1,
        )

    def test_assigning_adviser_creates_role_history(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        faculty = User.objects.create_user(
            username='faculty-adv-hist',
            password='pass12345',
            role='faculty',
        )

        response = self.client.patch(
            f'/api/users/{faculty.id}/',
            {'is_adviser': True},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        faculty.refresh_from_db()
        self.assertIsNone(faculty.adviser_phase)
        history = FacultyRoleAssignment.objects.filter(user=faculty)
        self.assertEqual(history.count(), 1)
        entry = history.first()
        self.assertEqual(entry.role_key, FacultyRoleAssignment.ROLE_ADVISER)
        self.assertEqual(entry.action, FacultyRoleAssignment.ACTION_ASSIGNED)
        self.assertIsNone(entry.role_detail)

    def test_list_returns_display_role_for_adviser(self):
        User.objects.create_user(
            username='faculty-adv-list',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )

        response = self.client.get('/api/users/')

        self.assertEqual(response.status_code, 200)
        adviser = next(
            u for u in response.data['users'] if u['username'] == 'faculty-adv-list'
        )
        self.assertEqual(adviser['displayRole']['label'], 'Adviser')
        self.assertEqual(adviser['displayRole']['tone'], 'adviser')

    def test_filter_by_adviser_role(self):
        User.objects.create_user(
            username='faculty-plain',
            password='pass12345',
            role='faculty',
        )
        User.objects.create_user(
            username='faculty-adv-filter',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )

        response = self.client.get('/api/users/?role=adviser')

        self.assertEqual(response.status_code, 200)
        usernames = {u['username'] for u in response.data['users']}
        self.assertIn('faculty-adv-filter', usernames)
        self.assertNotIn('faculty-plain', usernames)

    def test_user_role_assignment_history_endpoint(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        faculty = User.objects.create_user(
            username='faculty-role-hist',
            password='pass12345',
            role='faculty',
        )
        self.client.patch(
            f'/api/users/{faculty.id}/',
            {'is_adviser': True},
            format='json',
        )

        response = self.client.get(f'/api/users/{faculty.id}/role-assignments/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['assignments']), 1)
        self.assertEqual(response.data['assignments'][0]['role_label'], 'Project Adviser')
        self.assertEqual(response.data['assignments'][0]['action'], 'assigned')

    def test_user_adviser_assignment_history_endpoint(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        student = User.objects.create_user(
            username='2024-0099',
            password='pass12345',
            role='student',
        )
        adviser = User.objects.create_user(
            username='faculty-adv-2',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        team = StudentTeam.objects.create(
            name='Team History',
            project_title='History Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=semester,
            leader=student,
            adviser=adviser,
        )
        TeamAdviserAssignment.objects.create(
            team=team,
            adviser=adviser,
            assigned_by=self.admin,
            reason='Initial assignment',
        )

        response = self.client.get(f'/api/users/{adviser.id}/adviser-assignments/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['assignments']), 1)
        self.assertEqual(response.data['assignments'][0]['team_name'], 'Team History')
        self.assertEqual(response.data['assignments'][0]['reason'], 'Initial assignment')

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

    def test_guest_code_exchange_returns_access_token(self):
        schedule = self.create_defense_schedule()
        guest_code = GuestPanelistCode.objects.create(
            guest_name='External Panelist',
            defense_schedule=schedule,
            created_by=self.admin,
        )

        self.client.force_authenticate(user=None)
        response = self.client.post(
            '/api/users/guest-codes/exchange/',
            {'code': guest_code.code},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn('access', response.data)
        self.assertEqual(response.data['user']['role'], 'guest_panelist')
        self.assertEqual(response.data['user']['team_id'], schedule.team_id)

    def test_guest_code_exchange_rejects_invalid_code(self):
        self.client.force_authenticate(user=None)
        response = self.client.post(
            '/api/users/guest-codes/exchange/',
            {'code': 'DEF-INVALID'},
            format='json',
        )
        self.assertEqual(response.status_code, 401)

    def test_guest_assignments_and_submit_grades(self):
        schedule = self.create_defense_schedule()
        guest_code = GuestPanelistCode.objects.create(
            guest_name='External Panelist',
            defense_schedule=schedule,
            created_by=self.admin,
        )

        self.client.force_authenticate(user=None)
        exchange = self.client.post(
            '/api/users/guest-codes/exchange/',
            {'code': guest_code.code},
            format='json',
        )
        access = exchange.data['access']

        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access}')
        assignments = self.client.get('/api/defense/schedules/guest-assignments/')
        self.assertEqual(assignments.status_code, 200)
        self.assertEqual(len(assignments.data['teams']), 1)
        self.assertEqual(assignments.data['teams'][0]['id'], schedule.team_id)

        submit = self.client.post(
            '/api/defense/schedules/guest-submit-grades/',
            {
                'team_id': schedule.team_id,
                'schedule_id': schedule.id,
                'criteria_scores': [
                    {'name': 'Technical', 'score': 8, 'max_score': 10},
                ],
            },
            format='json',
        )
        self.assertEqual(submit.status_code, 201)
        self.assertTrue(submit.data['success'])

        wrong_team = self.client.post(
            '/api/defense/schedules/guest-submit-grades/',
            {
                'team_id': schedule.team_id + 9999,
                'schedule_id': schedule.id,
                'criteria_scores': [
                    {'name': 'Technical', 'score': 8, 'max_score': 10},
                ],
            },
            format='json',
        )
        self.assertEqual(wrong_team.status_code, 403)
