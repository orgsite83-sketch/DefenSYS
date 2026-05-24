from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from .models import SchoolYear, Semester


User = get_user_model()


class AcademicPeriodApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
        )
        self.client.force_authenticate(user=self.admin)

    def test_create_school_year_uses_prototype_format(self):
        response = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2027'},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['school_year']['label'], '2026-2027')
        self.assertIsNone(response.data['active_semester'])
        self.assertTrue(SchoolYear.objects.filter(label='2026-2027').exists())

    def test_rejects_invalid_and_duplicate_school_years(self):
        invalid = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2028'},
            format='json',
        )
        self.assertEqual(invalid.status_code, 400)

        SchoolYear.objects.create(label='2026-2027')
        duplicate = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2027'},
            format='json',
        )

        self.assertEqual(duplicate.status_code, 400)

    def test_create_semester_for_school_year(self):
        school_year = SchoolYear.objects.create(label='2026-2027')

        response = self.client.post(
            f'/api/academic-periods/{school_year.id}/semesters/',
            {'label': Semester.FIRST},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['semester']['label'], Semester.FIRST)
        self.assertFalse(response.data['semester']['is_active'])

    def test_activation_keeps_only_one_semester_active(self):
        first_year = SchoolYear.objects.create(label='2026-2027')
        second_year = SchoolYear.objects.create(label='2027-2028')
        first = Semester.objects.create(school_year=first_year, label=Semester.FIRST)
        second = Semester.objects.create(school_year=second_year, label=Semester.SECOND)

        first_response = self.client.patch(
            f'/api/academic-periods/semesters/{first.id}/',
            {'is_active': True},
            format='json',
        )
        second_response = self.client.patch(
            f'/api/academic-periods/semesters/{second.id}/',
            {'is_active': True},
            format='json',
        )

        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(second_response.status_code, 200)
        self.assertFalse(first.is_active)
        self.assertTrue(second.is_active)
        self.assertEqual(
            second_response.data['active_semester']['display_name'],
            '2nd Semester, A.Y. 2027-2028',
        )

    def test_student_cannot_patch_active_semester(self):
        student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST)

        self.client.force_authenticate(user=student)
        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'is_active': True},
            format='json',
        )

        self.assertEqual(response.status_code, 403)

    def test_student_cannot_create_school_year(self):
        student = User.objects.create_user(
            username='student-create',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2028-2029'},
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_list_includes_capstone_mode_on_active_semester(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )

        response = self.client.get('/api/academic-periods/')

        self.assertEqual(response.status_code, 200)
        active = response.data['active_semester']
        self.assertEqual(active['capstone_mode'], 'capstone_1_intake')
        self.assertTrue(active['can_create_capstone_teams'])
        self.assertIn('capstone_mode_message', active)

    def test_patch_semester_evaluation_flags(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )

        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {
                'capstone_peer_evaluation_enabled': False,
                'capstone_adviser_grading_enabled': False,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        semester.refresh_from_db()
        self.assertFalse(semester.capstone_peer_evaluation_enabled)
        self.assertFalse(semester.capstone_adviser_grading_enabled)
        self.assertEqual(
            response.data['semester']['capstone_peer_evaluation_enabled'],
            False,
        )

    def test_student_cannot_patch_evaluation_flags(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        student = User.objects.create_user(
            username='student-eval',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'capstone_peer_evaluation_enabled': False},
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_dashboard_reads_active_semester(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester'], '1st Semester, A.Y. 2026-2027')
        self.assertEqual(response.data['migration']['phase'], 15)
