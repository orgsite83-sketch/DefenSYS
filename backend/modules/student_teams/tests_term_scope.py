from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from user_management.academic_records.models import StudentAcademicRecord

from .models import StudentTeam, TeamMembership


User = get_user_model()


class TermScopeTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-term',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.pit_lead = User.objects.create_user(
            username='pit-3rd',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.student = User.objects.create_user(
            username='4081',
            password='pass12345',
            role='student',
            first_name='Carlos',
            last_name='Reyes',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.first_sem = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=False,
        )
        self.second_sem = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
            capstone_program_phase=Semester.PHASE_CAPSTONE_1,
            capstone_team_creation_enabled=True,
        )
        StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_sem,
            year_level='3rd Year',
        )
        StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.second_sem,
            year_level='3rd Year',
        )
        self.pit_team_first = StudentTeam.objects.create(
            name='Team PIT Old',
            project_title='Old PIT',
            level='3rd Year PIT',
            year_level='3rd Year',
            semester=self.first_sem,
            leader=self.student,
        )
        TeamMembership.objects.create(
            team=self.pit_team_first,
            student=self.student,
            is_leader=True,
            order=0,
        )

    def test_pit_lead_lists_only_active_term_teams_by_default(self):
        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/teams/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['teams']), 0)
        self.assertEqual(response.data['operating_mode'], 'audit')

        history = self.client.get('/api/teams/?scope=history')
        self.assertEqual(history.status_code, status.HTTP_200_OK)
        self.assertEqual(len(history.data['teams']), 1)
        self.assertEqual(history.data['teams'][0]['term_status'], 'historical')
        self.assertFalse(history.data['teams'][0]['is_editable'])

    def test_pit_lead_cannot_patch_historical_team(self):
        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.patch(
            f'/api/teams/{self.pit_team_first.id}/',
            {
                'name': 'Renamed',
                'project_title': 'Old PIT',
                'level': StudentTeam.LEVEL_3_PIT,
                'year_level': '3rd Year',
                'leader_id': self.student.id,
                'member_ids': [self.student.id],
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_reactivated_semester_allows_pit_lead_edit(self):
        self.second_sem.is_active = False
        self.second_sem.save(update_fields=['is_active'])
        self.first_sem.is_active = True
        self.first_sem.save(update_fields=['is_active'])

        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.patch(
            f'/api/teams/{self.pit_team_first.id}/',
            {
                'name': 'Team PIT Old',
                'project_title': 'Updated PIT',
                'level': StudentTeam.LEVEL_3_PIT,
                'year_level': '3rd Year',
                'leader_id': self.student.id,
                'member_ids': [self.student.id],
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.pit_team_first.refresh_from_db()
        self.assertEqual(self.pit_team_first.project_title, 'Updated PIT')

    def test_promoted_cohort_on_new_term_belongs_to_next_pit_lead(self):
        """After rollover to a new school year, 2nd Year PIT Lead sees promoted students on active term."""
        next_sy = SchoolYear.objects.create(label='2027-2028')
        new_first = Semester.objects.create(
            school_year=next_sy,
            label=Semester.FIRST,
            is_active=True,
        )
        self.second_sem.is_active = False
        self.second_sem.save(update_fields=['is_active'])

        promoted = User.objects.create_user(
            username='4082',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Lopez',
        )
        StudentAcademicRecord.objects.create(
            student=promoted,
            semester=new_first,
            year_level='2nd Year',
        )
        pit_2nd = User.objects.create_user(
            username='pit-2nd',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        self.client.force_authenticate(user=pit_2nd)
        response = self.client.get('/api/dashboards/pit-lead/cohort/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        usernames = {row['username'] for row in response.data['students']}
        self.assertIn('4082', usernames)
        self.assertNotIn('4081', usernames)

    def test_cohort_audit_mode_returns_historical_students(self):
        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/dashboards/pit-lead/cohort/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['operating_mode'], 'audit')
        self.assertGreaterEqual(len(response.data['history_students']), 1)
        self.assertTrue(
            any(row.get('is_historical') for row in response.data['history_students'])
        )
