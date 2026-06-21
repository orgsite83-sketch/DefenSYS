from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership

from .models import StudentAcademicRecord


User = get_user_model()


class StudentAcademicRecordApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
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
            capstone_team_creation_enabled=True,
            capstone_program_phase=Semester.PHASE_CAPSTONE_1,
        )
        self.client.force_authenticate(user=self.admin)

    def test_create_record_for_student_and_active_period_options(self):
        response = self.client.post(
            '/api/users/academic-records/',
            {
                'student_id': self.student.id,
                'semester_id': self.first_semester.id,
                'year_level': StudentAcademicRecord.FIRST_YEAR,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['record']['student_username'], '2024-0001')
        self.assertEqual(response.data['record']['school_year'], '2026-2027')
        self.assertEqual(response.data['record']['semester'], Semester.FIRST)

        list_response = self.client.get('/api/users/academic-records/')
        self.assertEqual(list_response.status_code, 200)
        self.assertEqual(list_response.data['active_semester']['id'], self.first_semester.id)
        self.assertEqual(list_response.data['students'][0]['username'], '2024-0001')

    def test_duplicate_student_semester_record_is_rejected(self):
        StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.FIRST_YEAR,
        )

        response = self.client.post(
            '/api/users/academic-records/',
            {
                'student_id': self.student.id,
                'semester_id': self.first_semester.id,
                'year_level': StudentAcademicRecord.FIRST_YEAR,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_non_student_user_is_rejected(self):
        faculty = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
        )

        response = self.client.post(
            '/api/users/academic-records/',
            {
                'student_id': faculty.id,
                'semester_id': self.first_semester.id,
                'year_level': StudentAcademicRecord.FIRST_YEAR,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_update_and_delete_record(self):
        record = StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.FIRST_YEAR,
        )

        update_response = self.client.patch(
            f'/api/users/academic-records/{record.id}/',
            {
                'student_id': self.student.id,
                'semester_id': self.second_semester.id,
                'year_level': StudentAcademicRecord.SECOND_YEAR,
            },
            format='json',
        )
        delete_response = self.client.delete(f'/api/users/academic-records/{record.id}/')

        self.assertEqual(update_response.status_code, 200)
        self.assertEqual(update_response.data['record']['semester'], Semester.SECOND)
        self.assertEqual(update_response.data['record']['year_level'], StudentAcademicRecord.SECOND_YEAR)
        self.assertEqual(delete_response.status_code, 200)
        self.assertFalse(StudentAcademicRecord.objects.filter(pk=record.id).exists())

    def test_rollover_promotes_retains_and_drops_latest_records(self):
        first = StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.FIRST_YEAR,
        )
        second_student = User.objects.create_user(
            username='2024-0002',
            password='pass12345',
            role='student',
            first_name='Ada',
        )
        second = StudentAcademicRecord.objects.create(
            student=second_student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.FIRST_YEAR,
        )

        self.first_semester.is_active = False
        self.first_semester.save(update_fields=['is_active'])
        self.second_semester.is_active = True
        self.second_semester.save(update_fields=['is_active'])

        preview = self.client.get('/api/users/academic-records/rollover-preview/')
        response = self.client.post(
            '/api/users/academic-records/rollover/',
            {
                'actions': [
                    {'record_id': first.id, 'action': 'promote'},
                    {'record_id': second.id, 'action': 'drop'},
                ],
            },
            format='json',
        )

        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview.data['rows'][0]['promote_result']['semester'], Semester.SECOND)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        promoted = StudentAcademicRecord.objects.get(rolled_from=first)
        self.assertEqual(promoted.semester, self.second_semester)
        self.assertEqual(promoted.year_level, StudentAcademicRecord.FIRST_YEAR)
        self.assertEqual(response.data['team_updates'], 0)

    def test_rollover_preserves_pit_memberships_on_capstone_intake(self):
        pit_team = StudentTeam.objects.create(
            name='Team CodeLearners',
            project_title='Smart Campus',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student,
        )
        TeamMembership.objects.create(
            team=pit_team,
            student=self.student,
            is_leader=True,
            order=0,
        )
        record = StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.THIRD_YEAR,
        )

        self.first_semester.is_active = False
        self.first_semester.save(update_fields=['is_active'])
        self.second_semester.is_active = True
        self.second_semester.save(update_fields=['is_active'])

        response = self.client.post(
            '/api/users/academic-records/rollover/',
            {'actions': [{'record_id': record.id, 'action': 'promote'}]},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertNotIn('pit_memberships_cleared', response.data)
        self.assertNotIn('pit_teams_emptied', response.data)
        self.assertTrue(
            TeamMembership.objects.filter(student=self.student, team=pit_team).exists(),
        )
        self.assertTrue(StudentTeam.objects.filter(pk=pit_team.id).exists())
        self.assertTrue(
            StudentAcademicRecord.objects.filter(
                student=self.student,
                semester=self.second_semester,
                year_level=StudentAcademicRecord.THIRD_YEAR,
            ).exists(),
        )

    def test_rollover_preserves_pit_history(self):
        pit_team = StudentTeam.objects.create(
            name='Team PIT',
            project_title='PIT Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.student,
        )
        TeamMembership.objects.create(
            team=pit_team,
            student=self.student,
            is_leader=True,
            order=0,
        )
        record = StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.second_semester,
            year_level=StudentAcademicRecord.SECOND_YEAR,
        )

        response = self.client.post(
            '/api/users/academic-records/rollover/',
            {'actions': [{'record_id': record.id, 'action': 'promote'}]},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertNotIn('pit_memberships_cleared', response.data)
        self.assertTrue(
            TeamMembership.objects.filter(student=self.student, team=pit_team).exists(),
        )

    def test_student_dashboard_includes_latest_academic_record(self):
        StudentAcademicRecord.objects.create(
            student=self.student,
            semester=self.first_semester,
            year_level=StudentAcademicRecord.FIRST_YEAR,
        )
        self.client.force_authenticate(user=self.student)

        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['academic_record']['school_year'], '2026-2027')
        self.assertEqual(response.data['academic_record']['semester'], Semester.FIRST)
        self.assertEqual(response.data['academic_record']['year_level'], StudentAcademicRecord.FIRST_YEAR)
