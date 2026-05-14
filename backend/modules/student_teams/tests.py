from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamMembership


User = get_user_model()


class StudentTeamApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.adviser = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
            first_name='Ada',
            last_name='Lovelace',
        )
        self.student_1 = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
        )
        self.student_2 = User.objects.create_user(
            username='2024-0002',
            password='pass12345',
            role='student',
            first_name='Maria',
            last_name='Santos',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.first_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.second_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
        )
        self.client.force_authenticate(user=self.admin)

    def test_create_team_uses_members_leader_adviser_and_active_semester(self):
        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team VaultSync',
                'project_title': 'Cloud File Sync for Students',
                'level': StudentTeam.LEVEL_3_CAPSTONE,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id, self.student_2.id],
                'adviser_id': self.adviser.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team']['semester'], Semester.FIRST)
        self.assertEqual(response.data['team']['member_count'], 2)
        self.assertEqual(response.data['team']['leader_name'], 'Juan Dela Cruz')
        self.assertEqual(response.data['team']['adviser_name'], 'Ada Lovelace')
        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.team_id, str(response.data['team']['id']))

    def test_duplicate_name_level_is_rejected(self):
        StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='Cloud File Sync',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )

        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team VaultSync',
                'level': StudentTeam.LEVEL_3_CAPSTONE,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_update_team_members_and_status(self):
        team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)

        response = self.client.patch(
            f'/api/teams/{team.id}/',
            {
                'name': 'Team Alpha',
                'project_title': 'Alpha Project Updated',
                'level': StudentTeam.LEVEL_4_CAPSTONE,
                'year_level': '4th Year',
                'semester_id': self.second_semester.id,
                'leader_id': self.student_2.id,
                'member_ids': [self.student_2.id],
                'adviser_id': self.adviser.id,
                'status': StudentTeam.STATUS_APPROVED,
            },
            format='json',
        )

        team.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(team.status, StudentTeam.STATUS_APPROVED)
        self.assertEqual(team.leader, self.student_2)
        self.assertEqual(team.memberships.count(), 1)

    def test_list_teams_returns_counts_and_options(self):
        StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )

        response = self.client.get('/api/teams/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['counts']['no_adviser'], 1)
        self.assertEqual(response.data['active_semester']['id'], self.first_semester.id)
        self.assertEqual(response.data['students'][0]['username'], '2024-0001')

    def test_bulk_import_creates_team_from_usernames(self):
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team CSV',
                        'project_title': 'CSV Project',
                        'level': StudentTeam.LEVEL_3_CAPSTONE,
                        'year_level': '3rd Year',
                        'member_ids': ['2024-0001', '2024-0002'],
                        'leader_id': '2024-0001',
                        'adviser_id': 'faculty-1',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(StudentTeam.objects.get(name='Team CSV').memberships.count(), 2)

    def test_student_dashboard_returns_real_team(self):
        team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)
        TeamMembership.objects.create(team=team, student=self.student_2, order=1)
        self.client.force_authenticate(user=self.student_1)

        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['team']['name'], 'Team Alpha')
        self.assertEqual(response.data['team']['memberCount'], 2)
        self.assertEqual(response.data['members'][0]['username'], '2024-0001')

    def test_admin_dashboard_counts_teams(self):
        StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['total_teams'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_rollover_advances_capstone_team_after_phase_six(self):
        record = StudentAcademicRecord.objects.create(
            student=self.student_1,
            semester=self.second_semester,
            year_level=StudentAcademicRecord.THIRD_YEAR,
        )
        team = StudentTeam.objects.create(
            name='Team Capstone',
            project_title='Capstone Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.second_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)

        response = self.client.post(
            '/api/student-records/rollover/',
            {'actions': [{'record_id': record.id, 'action': 'promote'}]},
            format='json',
        )

        team.refresh_from_db()
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team_updates'], 1)
        self.assertEqual(team.level, StudentTeam.LEVEL_4_CAPSTONE)
        self.assertEqual(team.capstone_phase, StudentTeam.PHASE_ACTIVE)
